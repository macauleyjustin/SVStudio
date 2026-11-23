import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import AudioToolbox
import SatellaCore

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

public final class LipSyncEngine: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let processor = LipSyncProcessor()
    private let sessionQueue = DispatchQueue(label: "dev.svstudio.lipsync.session", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "dev.svstudio.lipsync.audio", qos: .userInteractive)

    private var captureSession: AVCaptureSession?
    private var runtimeErrorObserver: NSObjectProtocol?
    private var sessionGeneration: UInt64 = 0

    private var currentMouthOpen: Double = 0.0
    private var rawRMSLevel: Double = 0.0
    private var activeStatus: LipSyncStatus = .inactive
    private var selectedDeviceUID: String?
    private var lastSampleTimestamp: CFAbsoluteTime = 0.0

    public override init() {
        super.init()
    }

    deinit {
        stop()
    }

    public func configure(noiseFloor: Double, gain: Double) {
        lock.lock()
        processor.configure(noiseFloor: noiseFloor, gain: gain)
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
        let updated = processor.calibrateNoiseFloor()
        lock.unlock()
        return updated
    }

    public static func enumerateInputDevices() -> [AudioInputDeviceInfo] {
        let coreAudioMap = coreAudioDeviceIDsByUID()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let connected = discovery.devices.filter(\.isConnected)
        if !connected.isEmpty {
            return connected.map { dev in
                AudioInputDeviceInfo(
                    id: dev.uniqueID,
                    name: dev.localizedName,
                    deviceID: coreAudioMap[dev.uniqueID] ?? 0
                )
            }
        }
        return coreAudioEnumerateFallback()
    }

    public func start(deviceUID: String?) {
        stop()
        lock.lock()
        sessionGeneration &+= 1
        let gen = sessionGeneration
        selectedDeviceUID = deviceUID
        activeStatus = .requestingPermission
        processor.reset()
        lastSampleTimestamp = 0.0
        lock.unlock()

        let devices = Self.enumerateInputDevices()
        if devices.isEmpty {
            setStatus(.noMicrophone, expectedGeneration: gen)
            return
        }

        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        switch auth {
        case .authorized:
            configureAndStartSession(preferredUID: deviceUID, devices: devices, generation: gen)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                guard self.isCurrentGeneration(gen) else { return }
                if granted {
                    self.configureAndStartSession(
                        preferredUID: deviceUID,
                        devices: Self.enumerateInputDevices(),
                        generation: gen
                    )
                } else {
                    self.setStatus(.permissionDenied, expectedGeneration: gen)
                }
            }
        case .denied, .restricted:
            setStatus(.permissionDenied, expectedGeneration: gen)
        @unknown default:
            setStatus(.permissionDenied, expectedGeneration: gen)
        }
    }

    public func stop() {
        lock.lock()
        sessionGeneration &+= 1
        let session = captureSession
        captureSession = nil
        let observer = runtimeErrorObserver
        runtimeErrorObserver = nil
        currentMouthOpen = 0.0
        rawRMSLevel = 0.0
        lastSampleTimestamp = 0.0
        processor.reset()
        activeStatus = .inactive
        lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let session {
            sessionQueue.async {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }
    }

    private func isCurrentGeneration(_ gen: UInt64) -> Bool {
        lock.lock()
        let matches = (gen == sessionGeneration)
        lock.unlock()
        return matches
    }

    private func setStatus(_ status: LipSyncStatus, expectedGeneration: UInt64? = nil) {
        lock.lock()
        if let expectedGeneration, expectedGeneration != sessionGeneration {
            lock.unlock()
            return
        }
        activeStatus = status
        lock.unlock()
    }

    private func configureAndStartSession(
        preferredUID: String?,
        devices: [AudioInputDeviceInfo],
        generation: UInt64
    ) {
        let targetUID = preferredUID ?? devices.first?.id
        let device = (targetUID.flatMap { AVCaptureDevice(uniqueID: $0) })
            ?? AVCaptureDevice.default(for: .audio)
            ?? devices.first.flatMap { AVCaptureDevice(uniqueID: $0.id) }

        guard let device else {
            setStatus(.noMicrophone, expectedGeneration: generation)
            return
        }

        sessionQueue.async { [weak self] in
            guard let self, self.isCurrentGeneration(generation) else { return }

            let session = AVCaptureSession()
            session.beginConfiguration()

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    self.setStatus(.error("Unable to add audio input \(device.localizedName)"), expectedGeneration: generation)
                    return
                }
                session.addInput(input)
            } catch {
                session.commitConfiguration()
                self.setStatus(.error(error.localizedDescription), expectedGeneration: generation)
                return
            }

            let output = AVCaptureAudioDataOutput()
            // Force normalized Float32 interleaved LinearPCM so mono/stereo and Int16/Float32 hardware mics (e.g. USB headsets) all work reliably.
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            output.setSampleBufferDelegate(self, queue: self.audioQueue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                self.setStatus(.error("Unable to attach audio output"), expectedGeneration: generation)
                return
            }
            session.addOutput(output)
            session.commitConfiguration()

            let errObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] note in
                guard let self, self.isCurrentGeneration(generation) else { return }
                let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                self.setStatus(
                    .error(err?.localizedDescription ?? "Microphone stream stopped"),
                    expectedGeneration: generation
                )
            }

            self.lock.lock()
            guard generation == self.sessionGeneration else {
                self.lock.unlock()
                NotificationCenter.default.removeObserver(errObserver)
                return
            }
            self.captureSession = session
            self.runtimeErrorObserver = errObserver
            self.activeStatus = .running
            self.lock.unlock()

            session.startRunning()
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else {
            return
        }
        let asbd = asbdPtr.pointee
        let totalFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard totalFrames > 0 else { return }

        var blockBuffer: CMBlockBuffer?
        var ablSizeNeeded = 0
        let probe = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &ablSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard probe == noErr, ablSizeNeeded > 0 else { return }

        let rawABL = UnsafeMutableRawPointer.allocate(byteCount: ablSizeNeeded, alignment: 16)
        defer { rawABL.deallocate() }
        let ablPtr = rawABL.assumingMemoryBound(to: AudioBufferList.self)
        let extract = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &ablSizeNeeded,
            bufferListOut: ablPtr,
            bufferListSize: ablSizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard extract == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard !buffers.isEmpty else { return }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bits = Int(asbd.mBitsPerChannel)

        var channels: [[Double]] = []
        if buffers.count == 1 {
            let ab = buffers[0]
            let chCount = max(1, Int(ab.mNumberChannels))
            guard let data = ab.mData, ab.mDataByteSize > 0 else { return }
            let framesAvailable: Int
            if isFloat && bits == 32 {
                let ptr = data.assumingMemoryBound(to: Float.self)
                framesAvailable = min(totalFrames, Int(ab.mDataByteSize) / (MemoryLayout<Float>.size * chCount))
                for c in 0..<chCount {
                    var arr = [Double]()
                    arr.reserveCapacity(framesAvailable)
                    for f in 0..<framesAvailable {
                        arr.append(Double(ptr[f * chCount + c]))
                    }
                    channels.append(arr)
                }
            } else if isSignedInt && bits == 16 {
                let ptr = data.assumingMemoryBound(to: Int16.self)
                framesAvailable = min(totalFrames, Int(ab.mDataByteSize) / (MemoryLayout<Int16>.size * chCount))
                let scale = 1.0 / 32768.0
                for c in 0..<chCount {
                    var arr = [Double]()
                    arr.reserveCapacity(framesAvailable)
                    for f in 0..<framesAvailable {
                        arr.append(Double(ptr[f * chCount + c]) * scale)
                    }
                    channels.append(arr)
                }
            } else if isSignedInt && bits == 32 {
                let ptr = data.assumingMemoryBound(to: Int32.self)
                framesAvailable = min(totalFrames, Int(ab.mDataByteSize) / (MemoryLayout<Int32>.size * chCount))
                let scale = 1.0 / 2147483648.0
                for c in 0..<chCount {
                    var arr = [Double]()
                    arr.reserveCapacity(framesAvailable)
                    for f in 0..<framesAvailable {
                        arr.append(Double(ptr[f * chCount + c]) * scale)
                    }
                    channels.append(arr)
                }
            }
        } else {
            for ab in buffers {
                guard let data = ab.mData, ab.mDataByteSize > 0 else { continue }
                if isFloat && bits == 32 {
                    let ptr = data.assumingMemoryBound(to: Float.self)
                    let count = min(totalFrames, Int(ab.mDataByteSize) / MemoryLayout<Float>.size)
                    channels.append((0..<count).map { Double(ptr[$0]) })
                } else if isSignedInt && bits == 16 {
                    let ptr = data.assumingMemoryBound(to: Int16.self)
                    let count = min(totalFrames, Int(ab.mDataByteSize) / MemoryLayout<Int16>.size)
                    let scale = 1.0 / 32768.0
                    channels.append((0..<count).map { Double(ptr[$0]) * scale })
                }
            }
        }
        guard !channels.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000.0
        lock.lock()
        let dt = lastSampleTimestamp > 0.0
            ? max(0.002, min(0.15, now - lastSampleTimestamp))
            : (Double(totalFrames) / sampleRate)
        lastSampleTimestamp = now
        let (mouthOpen, rms) = processor.processChannels(channels, sampleRate: sampleRate, dt: dt)
        rawRMSLevel = rms
        currentMouthOpen = mouthOpen
        lock.unlock()
    }

    private static func coreAudioDeviceIDsByUID() -> [String: AudioDeviceID] {
        var map: [String: AudioDeviceID] = [:]
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return map }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return map
        }
        for devID in ids {
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let st = withUnsafeMutablePointer(to: &uidRef) {
                AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, $0)
            }
            if st == noErr, let uid = uidRef?.takeRetainedValue() as String? {
                map[uid] = devID
            }
        }
        return map
    }

    private static func coreAudioEnumerateFallback() -> [AudioInputDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }

        var list: [AudioInputDeviceInfo] = []
        for devID in ids {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(devID, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &nameRef) {
                AudioObjectGetPropertyData(devID, &nameAddr, 0, nil, &nameSize, $0)
            }
            let name = (nameStatus == noErr ? nameRef?.takeRetainedValue() as String? : nil) ?? "Audio Input \(devID)"

            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = withUnsafeMutablePointer(to: &uidRef) {
                AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, $0)
            }
            let uid = (uidStatus == noErr ? uidRef?.takeRetainedValue() as String? : nil) ?? "\(devID)"
            list.append(AudioInputDeviceInfo(id: uid, name: name, deviceID: devID))
        }
        return list
    }
}
