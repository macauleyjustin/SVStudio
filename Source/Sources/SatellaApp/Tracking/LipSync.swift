import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import AudioToolbox

public struct AudioInputDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let deviceID: AudioDeviceID
}

public enum LipSyncStatus: Equatable, Sendable {
    case inactive
    case requestingPermission
    case running
    case noMicrophone
    case permissionDenied
    case error(String)

    public var descriptionText: String {
        switch self {
        case .inactive: return "Microphone Off"
        case .requestingPermission: return "Requesting Mic Access..."
        case .running: return "Listening"
        case .noMicrophone: return "No Microphone Found"
        case .permissionDenied: return "Mic Permission Denied"
        case .error(let msg): return "Mic Error: \(msg)"
        }
    }
}

public final class LipSyncEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var currentMouthOpen: Double = 0.0
    private var rawRMSLevel: Double = 0.0
    private var activeStatus: LipSyncStatus = .inactive
    private var noiseFloorRMS: Double = 0.032
    private var gainScale: Double = 1.6
    private var smoothedEnvelope: Double = 0.0
    private var isGateOpen: Bool = false
    private var selectedDeviceUID: String?

    public init() {}

    public func configure(noiseFloor: Double, gain: Double) {
        lock.lock()
        noiseFloorRMS = max(0.001, min(0.25, noiseFloor))
        gainScale = max(0.2, min(6.0, gain))
        lock.unlock()
    }

    public func readState() -> (mouthOpen: Double, level: Double, status: LipSyncStatus) {
        lock.lock()
        let out = (currentMouthOpen, rawRMSLevel, activeStatus)
        lock.unlock()
        return out
    }

    public func calibrateNoiseFloor() -> Double {
        lock.lock()
        let updated = max(0.008, min(0.18, rawRMSLevel * 1.45))
        noiseFloorRMS = updated
        lock.unlock()
        return updated
    }

    public static func enumerateInputDevices() -> [AudioInputDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }

        var list: [AudioInputDeviceInfo] = []
        for devID in ids {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(devID, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                continue
            }

            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &nameRef) { ptr in
                AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, ptr)
            }
            let name = (nameStatus == noErr ? nameRef?.takeRetainedValue() as String? : nil) ?? "Audio Input \(devID)"

            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = withUnsafeMutablePointer(to: &uidRef) { ptr in
                AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, ptr)
            }
            let uid = (uidStatus == noErr ? uidRef?.takeRetainedValue() as String? : nil) ?? "\(devID)"

            list.append(AudioInputDeviceInfo(id: uid, name: name, deviceID: devID))
        }
        return list
    }

    public func start(deviceUID: String?) {
        stop()
        lock.lock()
        selectedDeviceUID = deviceUID
        activeStatus = .requestingPermission
        lock.unlock()

        let devices = Self.enumerateInputDevices()
        if devices.isEmpty {
            setStatus(.noMicrophone)
            return
        }

        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        switch auth {
        case .authorized:
            startAudioEngine(devices: devices, preferredUID: deviceUID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startAudioEngine(devices: Self.enumerateInputDevices(), preferredUID: deviceUID)
                } else {
                    self.setStatus(.permissionDenied)
                }
            }
        case .denied, .restricted:
            setStatus(.permissionDenied)
        @unknown default:
            setStatus(.permissionDenied)
        }
    }

    public func stop() {
        lock.lock()
        let eng = engine
        engine = nil
        currentMouthOpen = 0.0
        rawRMSLevel = 0.0
        smoothedEnvelope = 0.0
        activeStatus = .inactive
        lock.unlock()

        if let eng {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
    }

    private func setStatus(_ status: LipSyncStatus) {
        lock.lock()
        activeStatus = status
        lock.unlock()
    }

    private func startAudioEngine(devices: [AudioInputDeviceInfo], preferredUID: String?) {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode

        if let uid = preferredUID, let match = devices.first(where: { $0.id == uid }),
           let au = inputNode.audioUnit {
            var devID = match.deviceID
            AudioUnitSetProperty(
                au,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
            setStatus(.noMicrophone)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processBuffer(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            lock.lock()
            engine = audioEngine
            activeStatus = .running
            lock.unlock()
        } catch {
            inputNode.removeTap(onBus: 0)
            setStatus(.error(error.localizedDescription))
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let ch0 = channels[0]
        var sumSq: Double = 0.0
        for i in 0..<frameCount {
            let s = Double(ch0[i])
            sumSq += s * s
        }
        let rms = sqrt(sumSq / Double(frameCount))

        lock.lock()
        let floor = noiseFloorRMS
        let gain = gainScale
        let enterGate = floor * 1.25 + 0.004
        let exitGate = floor * 1.05
        if isGateOpen {
            if rms < exitGate { isGateOpen = false }
        } else {
            if rms > enterGate { isGateOpen = true }
        }

        let normalized: Double
        if isGateOpen {
            let gated = max(0.0, rms - floor)
            let scaled = min(1.0, gated * gain * 5.2)
            // Super-linear onset curve suppresses faint breathing while keeping clear syllables expressive
            normalized = scaled < 0.04 ? 0.0 : pow(scaled, 1.32)
        } else {
            normalized = 0.0
        }

        let alpha = normalized > smoothedEnvelope ? 0.36 : 0.18
        smoothedEnvelope = smoothedEnvelope + (normalized - smoothedEnvelope) * alpha
        if smoothedEnvelope < 0.012 && !isGateOpen { smoothedEnvelope = 0.0 }
        rawRMSLevel = rms
        currentMouthOpen = smoothedEnvelope
        lock.unlock()
    }
}
