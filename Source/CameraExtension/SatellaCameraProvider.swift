import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo
import CoreAudio

/// Complete Apple CoreMediaIO Camera Extension (`CMIOExtensionProvider`) exposing both:
/// 1) A standard Camera Source stream visible as "Satella Virtual Camera" in Zoom, Chrome, Discord, FaceTime, and Photo Booth.
/// 2) A standard CMIO Sink stream accepting live frames pushed from Satella.app (`VirtualWebcamManager`).
///
/// Signing Note: macOS (`systemextensionsctl` / `sysextd`) requires an Apple Developer Team provisioning profile
/// with `com.apple.developer.system-extension.install` to activate a System Extension under SIP.
final class SatellaCameraExtensionProvider: NSObject, CMIOExtensionProviderSource {
    private let clientQueue = DispatchQueue(label: "dev.satella.camera.extension.provider")
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: SatellaCameraDeviceSource!

    override init() {
        super.init()
        self.provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        self.deviceSource = SatellaCameraDeviceSource(localizedName: "SVStudio Virtual Camera")
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            NSLog("SVStudioCameraExtension failed adding device: %@", error.localizedDescription)
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "SVStudio"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}

    func connect(to client: CMIOExtensionClient) throws {}
    func disconnect(from client: CMIOExtensionClient) {}
}

final class SatellaCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private let streamQueue = DispatchQueue(label: "dev.satella.camera.extension.stream")
    private var sourceStreamSource: SatellaStreamSource!
    private var sinkStreamSource: SatellaSinkStreamSource!
    private var bufferPool: CVPixelBufferPool!
    private var videoDescription: CMFormatDescription!
    private var idleTimer: DispatchSourceTimer?
    private var activeSinkClient: CMIOExtensionClient?
    private var sourceStreamingCount = 0

    static let deviceUUID = UUID(uuidString: "9B8F7C61-5D12-4A48-9B42-81A7E29D0001")!
    static let sourceUUID = UUID(uuidString: "9B8F7C61-5D12-4A48-9B42-81A7E29D0002")!
    static let sinkUUID = UUID(uuidString: "9B8F7C61-5D12-4A48-9B42-81A7E29D0003")!

    init(localizedName: String) {
        super.init()
        self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: Self.deviceUUID, legacyDeviceID: nil, source: self)

        let dims = CMVideoDimensions(width: 1280, height: 720)
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: dims.width,
            height: dims.height,
            extensions: nil,
            formatDescriptionOut: &videoDescription
        )
        let format = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: CMTime(value: 1, timescale: 30),
            minFrameDuration: CMTime(value: 1, timescale: 60),
            validFrameDurations: nil
        )

        self.sourceStreamSource = SatellaStreamSource(localizedName: "SVStudio Camera", streamID: Self.sourceUUID, format: format) { [weak self] active in
            self?.handleSourceStreamState(active)
        }
        self.sinkStreamSource = SatellaSinkStreamSource(
            localizedName: "SVStudio Camera Sink",
            streamID: Self.sinkUUID,
            format: format,
            onSinkFrame: { [weak self] sampleBuffer in
                self?.forwardSinkFrame(sampleBuffer)
            },
            onSinkStateChanged: { [weak self] client in
                self?.activeSinkClient = client
            }
        )

        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(dims.width),
            kCVPixelBufferHeightKey as String: Int(dims.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, poolAttrs as CFDictionary, &bufferPool)

        do {
            try device.addStream(sourceStreamSource.stream)
            try device.addStream(sinkStreamSource.stream)
        } catch {
            NSLog("SatellaCameraExtension addStream error: %@", error.localizedDescription)
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            props.transportType = Int(kAudioDeviceTransportTypeVirtual)
        }
        if properties.contains(.deviceModel) {
            props.model = "SVStudio Virtual Webcam 1.0"
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    private func handleSourceStreamState(_ active: Bool) {
        streamQueue.async { [weak self] in
            guard let self else { return }
            if active {
                self.sourceStreamingCount += 1
                if self.idleTimer == nil {
                    let t = DispatchSource.makeTimerSource(queue: self.streamQueue)
                    t.schedule(deadline: .now(), repeating: .milliseconds(33))
                    t.setEventHandler { [weak self] in
                        self?.emitStandbyFrameIfNoSink()
                        self?.pullSinkFrame()
                    }
                    self.idleTimer = t
                    t.resume()
                }
            } else {
                self.sourceStreamingCount = max(0, self.sourceStreamingCount - 1)
                if self.sourceStreamingCount == 0 {
                    self.idleTimer?.cancel()
                    self.idleTimer = nil
                }
            }
        }
    }

    private func pullSinkFrame() {
        guard let client = activeSinkClient else { return }
        sinkStreamSource.stream.consumeSampleBuffer(from: client) { [weak self] sample, _, discont, _, err in
            guard let self, err == nil, let sample else { return }
            self.sourceStreamSource.stream.send(
                sample,
                discontinuity: discont,
                hostTimeInNanoseconds: UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1e9)
            )
        }
    }

    private func forwardSinkFrame(_ sampleBuffer: CMSampleBuffer) {
        sourceStreamSource.stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1e9)
        )
    }

    private func emitStandbyFrameIfNoSink() {
        guard activeSinkClient == nil, let pool = bufferPool, let vDesc = videoDescription else { return }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess, let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            memset(base, 14, CVPixelBufferGetBytesPerRow(pb) * CVPixelBufferGetHeight(pb))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sbuf: CMSampleBuffer?
        if CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: vDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sbuf
        ) == noErr, let sbuf {
            forwardSinkFrame(sbuf)
        }
    }
}

final class SatellaStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let _formats: [CMIOExtensionStreamFormat]
    private let onStateChanged: (Bool) -> Void

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, onStateChanged: @escaping (Bool) -> Void) {
        self._formats = [format]
        self.onStateChanged = onStateChanged
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { _formats }
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { props.frameDuration = CMTime(value: 1, timescale: 30) }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }
    func startStream() throws { onStateChanged(true) }
    func stopStream() throws { onStateChanged(false) }
}

final class SatellaSinkStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let _formats: [CMIOExtensionStreamFormat]
    private var currentClient: CMIOExtensionClient?
    private let onSinkStateChanged: (CMIOExtensionClient?) -> Void

    init(
        localizedName: String,
        streamID: UUID,
        format: CMIOExtensionStreamFormat,
        onSinkFrame: @escaping (CMSampleBuffer) -> Void,
        onSinkStateChanged: @escaping (CMIOExtensionClient?) -> Void
    ) {
        self._formats = [format]
        self.onSinkStateChanged = onSinkStateChanged
        super.init()
        _ = onSinkFrame
        self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .sink, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { _formats }
    var availableProperties: Set<CMIOExtensionProperty> { [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup] }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { props.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { props.frameDuration = CMTime(value: 1, timescale: 30) }
        if properties.contains(.streamSinkBufferQueueSize) { props.sinkBufferQueueSize = 2 }
        if properties.contains(.streamSinkBuffersRequiredForStartup) { props.sinkBuffersRequiredForStartup = 1 }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        currentClient = client
        return true
    }

    func startStream() throws {
        onSinkStateChanged(currentClient)
    }

    func stopStream() throws {
        currentClient = nil
        onSinkStateChanged(nil)
    }
}

@main
enum SatellaCameraExtensionMain {
    static func main() {
        let provider = SatellaCameraExtensionProvider()
        CMIOExtensionProvider.startService(provider: provider.provider)
        CFRunLoopRun()
    }
}
