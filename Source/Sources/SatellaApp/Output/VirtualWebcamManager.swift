import Foundation
@preconcurrency import AppKit
@preconcurrency import CoreMediaIO
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
@preconcurrency import VideoToolbox
import SystemExtensions
import SatellaCore
import SatellaRender

public struct VirtualWebcamSinkInfo: Identifiable, Hashable, Sendable {
    public var id: String { "\(deviceID):\(streamID)" }
    public let deviceID: CMIODeviceID
    public let streamID: CMIOStreamID
    public let deviceName: String
    public let width: Int
    public let height: Int
    public let pixelFormat: OSType
}

public enum VirtualWebcamStatus: Equatable, Sendable {
    case stopped
    case streaming(deviceName: String, width: Int, height: Int, fps: Double)
    case waitingForExtension
    case error(String)

    public var descriptionText: String {
        switch self {
        case .stopped:
            return "Virtual Webcam Off"
        case .streaming(let name, let w, let h, let fps):
            return String(format: "Streaming -> %@ (%dx%d @ %.0f fps)", name, w, h, fps)
        case .waitingForExtension:
            return "No active macOS Camera Extension sink found"
        case .error(let msg):
            return "Webcam Error: \(msg)"
        }
    }
}

/// Pushes live Metal-rendered avatar frames via Apple's documented CoreMediaIO Sink Stream API
/// (`CMIODeviceStartStream` + `CMIOStreamCopyBufferQueue`) to any active macOS Virtual Camera Sink
/// (such as OBS Virtual Camera when enabled in System Settings, or a signed Satella Camera Extension).
public final class VirtualWebcamManager: NSObject, @unchecked Sendable, OSSystemExtensionRequestDelegate {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.satella.virtualcam.stream", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private weak var renderEngine: RenderEngine?
    private var activeSink: VirtualWebcamSinkInfo?
    private var sinkQueue: CMSimpleQueue?
    private var bgraBufferPool: CVPixelBufferPool?
    private var transferSession: VTPixelTransferSession?
    private var outputBufferPool: CVPixelBufferPool?
    private var targetWidth: Int = 1280
    private var targetHeight: Int = 720
    private var targetPixelFormat: OSType = kCVPixelFormatType_32BGRA

    private var currentStatus: VirtualWebcamStatus = .stopped
    private var latestSnapshot: (() -> LiveRenderSnapshot?)?
    private var frameIndex: Int64 = 0
    private var isBusy: Bool = false
    private var extensionStatusMessage: String?

    public override init() {
        super.init()
    }

    public static func hasEmbeddedCameraExtension() -> Bool {
        guard let url = Bundle.main.builtInPlugInsURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Library/SystemExtensions/dev.svstudio.camera.extension.systemextension") else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func openCameraExtensionsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    public func installEmbeddedExtensionIfPresent() {
        guard Self.hasEmbeddedCameraExtension() else {
            lock.lock()
            extensionStatusMessage = "Unsigned ad-hoc build: sign with an Apple Developer ID to embed SVStudio Virtual Camera, or enable OBS Virtual Camera in System Settings."
            lock.unlock()
            return
        }
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "dev.svstudio.camera.extension",
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    public nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    public nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        lock.lock()
        extensionStatusMessage = "Approve Satella Camera in System Settings -> Login Items & Extensions -> Camera Extensions."
        lock.unlock()
    }

    public nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        lock.lock()
        extensionStatusMessage = result == .completed ? "Satella Camera Extension activated." : "Satella Camera Extension requires reboot to activate."
        lock.unlock()
    }

    public nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        lock.lock()
        extensionStatusMessage = "Camera Extension activation declined by macOS: \(error.localizedDescription)"
        lock.unlock()
    }

    public static func discoverSinkDevices() -> [VirtualWebcamSinkInfo] {
        var devAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var devSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &devAddr, 0, nil, &devSize) == noErr,
              devSize > 0 else {
            return []
        }
        let devCount = Int(devSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: devCount)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &devAddr, 0, nil, devSize, &devSize, &devices) == noErr else {
            return []
        }

        var sinks: [VirtualWebcamSinkInfo] = []
        for dev in devices {
            let name = copyStringProperty(objectID: dev, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName)) ?? "CMIO Device \(dev)"

            var streamAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var streamSize: UInt32 = 0
            guard CMIOObjectGetPropertyDataSize(dev, &streamAddr, 0, nil, &streamSize) == noErr, streamSize > 0 else {
                continue
            }
            let streamCount = Int(streamSize) / MemoryLayout<CMIOStreamID>.size
            var streams = [CMIOStreamID](repeating: 0, count: streamCount)
            guard CMIOObjectGetPropertyData(dev, &streamAddr, 0, nil, streamSize, &streamSize, &streams) == noErr else {
                continue
            }

            for st in streams {
                // kCMIOStreamPropertyDirection == 0 indicates output (Sink) stream accepting pushed CMSampleBuffers
                var dirAddr = CMIOObjectPropertyAddress(
                    mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyDirection),
                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
                )
                var dir: UInt32 = 1
                var dirSize = UInt32(MemoryLayout<UInt32>.size)
                guard CMIOObjectGetPropertyData(st, &dirAddr, 0, nil, dirSize, &dirSize, &dir) == noErr,
                      dir == 0 else {
                    continue
                }

                let (w, h, fmt) = queryStreamFormat(streamID: st)
                sinks.append(VirtualWebcamSinkInfo(
                    deviceID: dev,
                    streamID: st,
                    deviceName: name,
                    width: w,
                    height: h,
                    pixelFormat: fmt
                ))
            }
        }
        return sinks
    }

    private static func copyStringProperty(objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var addr = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var ref: Unmanaged<CFString>?
        let err = withUnsafeMutablePointer(to: &ref) { ptr in
            CMIOObjectGetPropertyData(objectID, &addr, 0, nil, size, &size, ptr)
        }
        guard err == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    private static func queryStreamFormat(streamID: CMIOStreamID) -> (Int, Int, OSType) {
        var fmtAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOStreamPropertyFormatDescription),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size = UInt32(MemoryLayout<Unmanaged<CMFormatDescription>?>.size)
        var fmtRef: Unmanaged<CMFormatDescription>?
        let err = withUnsafeMutablePointer(to: &fmtRef) { ptr in
            CMIOObjectGetPropertyData(streamID, &fmtAddr, 0, nil, size, &size, ptr)
        }
        if err == noErr, let desc = fmtRef?.takeRetainedValue() {
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let sub = CMFormatDescriptionGetMediaSubType(desc)
            if dims.width > 0 && dims.height > 0 {
                return (Int(dims.width), Int(dims.height), sub)
            }
        }
        return (1280, 720, kCVPixelFormatType_32BGRA)
    }

    public func readStatus() -> (status: VirtualWebcamStatus, extensionNote: String?) {
        lock.lock()
        let out = (currentStatus, extensionStatusMessage)
        lock.unlock()
        return out
    }

    private static let queueAlteredCallback: CMIODeviceStreamQueueAlteredProc = { _, _, _ in }

    public func start(
        sinkID: String?,
        fps: Double = 30.0,
        renderEngine: RenderEngine,
        snapshotProvider: @escaping @Sendable () -> LiveRenderSnapshot?
    ) {
        stop()

        let sinks = Self.discoverSinkDevices()
        guard let sink = (sinkID.flatMap { id in sinks.first { $0.id == id } }) ?? sinks.first else {
            lock.lock()
            currentStatus = .waitingForExtension
            lock.unlock()
            return
        }

        var rawQueue: Unmanaged<CMSimpleQueue>?
        let qErr = CMIOStreamCopyBufferQueue(sink.streamID, Self.queueAlteredCallback, nil, &rawQueue)
        guard qErr == noErr, let simQueue = rawQueue?.takeRetainedValue() else {
            lock.lock()
            currentStatus = .error("Unable to acquire CMIO sink queue (status \(qErr)).")
            lock.unlock()
            return
        }

        let startErr = CMIODeviceStartStream(sink.deviceID, sink.streamID)
        if startErr != noErr {
            lock.lock()
            currentStatus = .error("CMIODeviceStartStream failed (status \(startErr)).")
            lock.unlock()
            return
        }

        guard let bgraPool = createPool(width: sink.width, height: sink.height, format: kCVPixelFormatType_32BGRA) else {
            CMIODeviceStopStream(sink.deviceID, sink.streamID)
            lock.lock()
            currentStatus = .error("Unable to allocate IOSurface CVPixelBufferPool.")
            lock.unlock()
            return
        }

        var outPool: CVPixelBufferPool?
        var vtSession: VTPixelTransferSession?
        if sink.pixelFormat != kCVPixelFormatType_32BGRA {
            outPool = createPool(width: sink.width, height: sink.height, format: sink.pixelFormat)
            VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &vtSession)
        }

        lock.lock()
        self.renderEngine = renderEngine
        self.latestSnapshot = snapshotProvider
        self.activeSink = sink
        self.sinkQueue = simQueue
        self.bgraBufferPool = bgraPool
        self.outputBufferPool = outPool
        self.transferSession = vtSession
        self.targetWidth = sink.width
        self.targetHeight = sink.height
        self.targetPixelFormat = sink.pixelFormat
        self.frameIndex = 0
        self.currentStatus = .streaming(deviceName: sink.deviceName, width: sink.width, height: sink.height, fps: fps)
        lock.unlock()

        let intervalNs = UInt64((1_000_000_000.0 / max(15.0, min(60.0, fps))).rounded())
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(intervalNs)), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.pushFrame()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil

        lock.lock()
        let prevSink = activeSink
        activeSink = nil
        sinkQueue = nil
        bgraBufferPool = nil
        outputBufferPool = nil
        if let vt = transferSession {
            VTPixelTransferSessionInvalidate(vt)
        }
        transferSession = nil
        latestSnapshot = nil
        currentStatus = .stopped
        lock.unlock()

        if let prevSink {
            CMIODeviceStopStream(prevSink.deviceID, prevSink.streamID)
        }
    }

    private func createPool(width: Int, height: Int, format: OSType) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: (format == kCVPixelFormatType_32BGRA)
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        return pool
    }

    private func pushFrame() {
        lock.lock()
        if isBusy {
            lock.unlock()
            return
        }
        isBusy = true
        let engine = renderEngine
        let snapProvider = latestSnapshot
        let simQueue = sinkQueue
        let bgraPool = bgraBufferPool
        let outPool = outputBufferPool
        let vt = transferSession
        let targetFmt = targetPixelFormat
        let ptsIndex = frameIndex
        frameIndex += 1
        lock.unlock()

        defer {
            lock.lock()
            isBusy = false
            lock.unlock()
        }

        guard let engine, let snap = snapProvider?(), let simQueue, let bgraPool else { return }

        // Keep queue latency under 2 frames
        if CMSimpleQueueGetCount(simQueue) >= max(2, CMSimpleQueueGetCapacity(simQueue) - 1) {
            return
        }

        var bgraOpt: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bgraPool, &bgraOpt) == kCVReturnSuccess,
              let bgraPB = bgraOpt else {
            return
        }

        do {
            // Virtual webcam always outputs solid pixels (green/black/white/custom) cleanly for external video apps
            let camBg: SatBackgroundMode = (snap.background == .transparent || snap.background == .checkerboard)
                ? .black
                : snap.background
            try engine.renderFrame(
                into: bgraPB,
                canvasSize: snap.canvasSize,
                camera: snap.camera,
                drawables: snap.drawables,
                effects: snap.effects,
                background: camBg,
                customColor: snap.customColor
            )
        } catch {
            return
        }

        var finalPB = bgraPB
        if targetFmt != kCVPixelFormatType_32BGRA, let outPool, let vt {
            var convOpt: CVPixelBuffer?
            if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outPool, &convOpt) == kCVReturnSuccess,
               let convPB = convOpt,
               VTPixelTransferSessionTransferImage(vt, from: bgraPB, to: convPB) == noErr {
                finalPB = convPB
            }
        }

        var formatDesc: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: finalPB,
            formatDescriptionOut: &formatDesc
        ) == noErr, let fDesc = formatDesc else {
            return
        }

        let nowSec = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: nowSec,
            decodeTimeStamp: .invalid
        )
        _ = ptsIndex

        var sampleOpt: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: finalPB,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleOpt
        ) == noErr, let sample = sampleOpt else {
            return
        }

        let rawBuffer = Unmanaged.passRetained(sample).toOpaque()
        let enqErr = CMSimpleQueueEnqueue(simQueue, element: rawBuffer)
        if enqErr != noErr {
            Unmanaged<CMSampleBuffer>.fromOpaque(rawBuffer).release()
        }
    }
}
