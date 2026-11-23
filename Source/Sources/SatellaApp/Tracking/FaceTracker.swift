import Foundation
@preconcurrency import AVFoundation
import Vision
import SatellaCore

public struct CameraDeviceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public enum FaceTrackerStatus: Equatable, Sendable {
    case inactive
    case requestingPermission
    case running(faceDetected: Bool, handsDetected: Int = 0)
    case noCamera
    case permissionDenied
    case error(String)

    public var descriptionText: String {
        switch self {
        case .inactive:
            return "Camera Off"
        case .requestingPermission:
            return "Requesting Camera Access..."
        case .running(let face, let hands):
            if face && hands > 0 {
                return "Face + \(hands) Hand\(hands > 1 ? "s" : "")"
            } else if face {
                return "Face Detected"
            } else if hands > 0 {
                return "\(hands) Hand\(hands > 1 ? "s" : "") Tracked"
            } else {
                return "Searching for Face..."
            }
        case .noCamera:
            return "No Camera Found"
        case .permissionDenied:
            return "Camera Permission Denied"
        case .error(let msg):
            return "Camera Error: \(msg)"
        }
    }
}

/// Unified native macOS webcam tracker using AVFoundation + Apple Vision.
/// Runs both `VNDetectFaceLandmarksRequest` (roll-corrected expressions, pupils, brows, cheeks)
/// and `VNDetectHumanHandPoseRequest` (up to 2 hands with 5-finger articulation) on a single capture session.
public final class FaceTracker: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private let sessionQueue = DispatchQueue(label: "dev.svstudio.tracker.session")
    private let visionQueue = DispatchQueue(label: "dev.svstudio.tracker.vision")

    private var session: AVCaptureSession?
    private var latestSample = TrackingSample()
    private var status: FaceTrackerStatus = .inactive

    public var trackingMode: CameraTrackingMode = .faceOnly
    public var mirrorHands: Bool = true

    // Face & expression calibration baselines
    private var lastRawYawDeg: Double = 0.0
    private var lastRawPitchDeg: Double = 0.0
    private var lastRawRollDeg: Double = 0.0
    private var lastRawPosX: Double = 0.0
    private var lastRawPosY: Double = 0.0
    private var lastRawBoxW: Double = 0.28
    private var lastRawMouthRatio: Double = 0.08
    private var lastRawBrowLift: Double = 0.16
    private var lastRawSignedSmile: Double = 0.0

    private var neutralYawOffset: Double = 0.0
    private var neutralPitchOffset: Double = 0.0
    private var neutralRollOffset: Double = 0.0
    private var neutralPosXOffset: Double = 0.0
    private var neutralPosYOffset: Double = 0.0
    private var neutralBoxWidth: Double = 0.28
    private var neutralMouthBaseline: Double = 0.095
    private var adaptiveClosedFloor: Double = 0.095
    private var mouthIsCurrentlyOpen: Bool = false
    private var browLiftBaseline: Double = 0.16
    private var neutralSmileBaseline: Double = 0.0
    private var autoCalibSamples: Int = 0
    private var autoCalibBrowSum: Double = 0.0
    private var autoCalibSmileSum: Double = 0.0
    private var autoCalibWidthSum: Double = 0.0

    private var candidateExpression: String = "neutral"
    private var candidateExprCount: Int = 0
    private var stableDetectedExpression: String = "neutral"

    private var lastFaceTimestamp: CFAbsoluteTime = 0.0
    private var lastHandLTimestamp: CFAbsoluteTime = 0.0
    private var lastHandRTimestamp: CFAbsoluteTime = 0.0
    private var isProcessingFrame = false

    public override init() {
        super.init()
    }

    public static func enumerateCameras() -> [CameraDeviceInfo] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    public func readState() -> (sample: TrackingSample, status: FaceTrackerStatus) {
        lock.lock()
        var s = latestSample
        let now = CFAbsoluteTimeGetCurrent()
        if s.isFaceDetected && (now - lastFaceTimestamp) > 0.65 {
            s.isFaceDetected = false
            latestSample.isFaceDetected = false
        }
        if s.handLeft.found && (now - lastHandLTimestamp) > 0.45 {
            s.handLeft = HandTrackingSample()
            latestSample.handLeft = HandTrackingSample()
        }
        if s.handRight.found && (now - lastHandRTimestamp) > 0.45 {
            s.handRight = HandTrackingSample()
            latestSample.handRight = HandTrackingSample()
        }
        let handCount = (s.handLeft.found ? 1 : 0) + (s.handRight.found ? 1 : 0)
        if case .running = status {
            status = .running(faceDetected: s.isFaceDetected, handsDetected: handCount)
        }
        let finalStatus = status
        lock.unlock()
        return (s, finalStatus)
    }

    public func calibrateNeutral() {
        lock.lock()
        neutralYawOffset = lastRawYawDeg
        neutralPitchOffset = lastRawPitchDeg
        neutralRollOffset = lastRawRollDeg
        neutralPosXOffset = lastRawPosX
        neutralPosYOffset = lastRawPosY
        neutralBoxWidth = max(0.12, lastRawBoxW)
        neutralMouthBaseline = max(0.04, min(0.18, lastRawMouthRatio))
        adaptiveClosedFloor = neutralMouthBaseline
        mouthIsCurrentlyOpen = false
        browLiftBaseline = max(0.06, min(0.32, lastRawBrowLift))
        neutralSmileBaseline = max(-0.22, min(0.22, lastRawSignedSmile))
        autoCalibSamples = 8
        candidateExpression = "neutral"
        candidateExprCount = 0
        stableDetectedExpression = "neutral"
        lock.unlock()
    }

    public func start(cameraID: String?) {
        stop()
        let cameras = Self.enumerateCameras()
        if cameras.isEmpty {
            setStatus(.noCamera)
            return
        }

        setStatus(.requestingPermission)
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        switch auth {
        case .authorized:
            configureAndStart(cameraID: cameraID, cameras: cameras)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart(cameraID: cameraID, cameras: Self.enumerateCameras())
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
        let cap = session
        session = nil
        latestSample = TrackingSample()
        status = .inactive
        autoCalibSamples = 0
        autoCalibBrowSum = 0.0
        autoCalibSmileSum = 0.0
        autoCalibWidthSum = 0.0
        lock.unlock()

        if let cap {
            sessionQueue.async {
                if cap.isRunning { cap.stopRunning() }
            }
        }
    }

    private func setStatus(_ newStatus: FaceTrackerStatus) {
        lock.lock()
        status = newStatus
        lock.unlock()
    }

    private func configureAndStart(cameraID: String?, cameras: [CameraDeviceInfo]) {
        let targetID = cameraID ?? cameras.first?.id
        guard let targetID, let device = AVCaptureDevice(uniqueID: targetID) ?? AVCaptureDevice.default(for: .video) else {
            setStatus(.noCamera)
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let capture = AVCaptureSession()
            capture.beginConfiguration()
            capture.sessionPreset = .vga640x480

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if capture.canAddInput(input) {
                    capture.addInput(input)
                } else {
                    capture.commitConfiguration()
                    self.setStatus(.error("Unable to add camera input"))
                    return
                }
            } catch {
                capture.commitConfiguration()
                self.setStatus(.error(error.localizedDescription))
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.visionQueue)
            if capture.canAddOutput(output) {
                capture.addOutput(output)
            } else {
                capture.commitConfiguration()
                self.setStatus(.error("Unable to add video output"))
                return
            }
            capture.commitConfiguration()

            self.lock.lock()
            self.session = capture
            self.status = .running(faceDetected: false, handsDetected: 0)
            self.lock.unlock()

            capture.startRunning()
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        if isProcessingFrame {
            lock.unlock()
            return
        }
        isProcessingFrame = true
        let mode = trackingMode
        let mirror = mirrorHands
        lock.unlock()

        defer {
            lock.lock()
            isProcessingFrame = false
            lock.unlock()
        }

        var faceReq: VNDetectFaceLandmarksRequest?
        var handReq: VNDetectHumanHandPoseRequest?
        var requests: [VNRequest] = []

        if mode.tracksFace {
            let req = VNDetectFaceLandmarksRequest()
            faceReq = req
            requests.append(req)
        }
        if mode.tracksHands {
            let req = VNDetectHumanHandPoseRequest()
            req.maximumHandCount = 2
            handReq = req
            requests.append(req)
        }
        guard !requests.isEmpty else { return }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .upMirrored, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let parsedFace = faceReq.flatMap { parseFaceResult($0.results?.first) }
        let parsedHands = handReq.map { parseHandsResult($0.results ?? [], mirror: mirror) }

        lock.lock()
        if let f = parsedFace {
            applyFaceMetrics(f, now: now)
        } else if !mode.tracksFace || (now - lastFaceTimestamp) > 0.65 {
            clearFaceFields()
        }

        if let hands = parsedHands {
            if let l = hands.left {
                latestSample.handLeft = l
                lastHandLTimestamp = now
            } else if (now - lastHandLTimestamp) > 0.35 {
                latestSample.handLeft = HandTrackingSample()
            }
            if let r = hands.right {
                latestSample.handRight = r
                lastHandRTimestamp = now
            } else if (now - lastHandRTimestamp) > 0.35 {
                latestSample.handRight = HandTrackingSample()
            }
            latestSample.handDistance = hands.distance
        } else if !mode.tracksHands {
            latestSample.handLeft = HandTrackingSample()
            latestSample.handRight = HandTrackingSample()
            latestSample.handDistance = 0.0
        }

        let hc = (latestSample.handLeft.found ? 1 : 0) + (latestSample.handRight.found ? 1 : 0)
        status = .running(faceDetected: latestSample.isFaceDetected, handsDetected: hc)
        lock.unlock()
    }

    // MARK: - Face & Roll-Aligned Expression Analysis

    private struct ParsedFaceMetrics {
        var rawYaw: Double
        var rawPitch: Double
        var rawRoll: Double
        var rawPosX: Double
        var rawPosY: Double
        var rawBoxW: Double
        var rawMouthRatio: Double
        var rawSignedSmile: Double
        var mouthX: Double
        var eyeL: Double
        var eyeR: Double
        var gazeX: Double
        var gazeY: Double
        var rawBrowLiftL: Double
        var rawBrowLiftR: Double
        var innerSlopeL: Double
        var innerSlopeR: Double
        var confidence: Double
    }

    private func parseFaceResult(_ observation: VNFaceObservation?) -> ParsedFaceMetrics? {
        guard let face = observation, face.confidence >= 0.30 else { return nil }
        let radToDeg = 180.0 / Double.pi
        let rawYaw = -(face.yaw?.doubleValue ?? 0.0) * radToDeg * 1.48
        let rawRoll = (face.roll?.doubleValue ?? 0.0) * radToDeg * 1.32

        let box = face.boundingBox
        let rawPosX = (Double(box.midX) - 0.5) * 16.0
        let rawPosY = (Double(box.midY) - 0.5) * 16.0
        let rawBoxW = Double(box.width)

        var eyeSpan = 0.36
        var lEyeCenter = CGPoint(x: 0.32, y: 0.62)
        var rEyeCenter = CGPoint(x: 0.68, y: 0.62)
        var rollRad = 0.0

        if let landmarks = face.landmarks,
           let lPts = landmarks.leftEye?.normalizedPoints, !lPts.isEmpty,
           let rPts = landmarks.rightEye?.normalizedPoints, !rPts.isEmpty {
            lEyeCenter = CGPoint(
                x: lPts.reduce(0.0) { $0 + Double($1.x) } / Double(lPts.count),
                y: lPts.reduce(0.0) { $0 + Double($1.y) } / Double(lPts.count)
            )
            rEyeCenter = CGPoint(
                x: rPts.reduce(0.0) { $0 + Double($1.x) } / Double(rPts.count),
                y: rPts.reduce(0.0) { $0 + Double($1.y) } / Double(rPts.count)
            )
            let dx = Double(rEyeCenter.x - lEyeCenter.x)
            let dy = Double(rEyeCenter.y - lEyeCenter.y)
            eyeSpan = max(0.14, hypot(dx, dy))
            rollRad = atan2(dy, dx)
        }

        // De-rotate every landmark point around the mid-eye pivot so head roll doesn't skew smiles or brows
        let pivot = CGPoint(x: (lEyeCenter.x + rEyeCenter.x) * 0.5, y: (lEyeCenter.y + rEyeCenter.y) * 0.5)
        let cosR = cos(-rollRad)
        let sinR = sin(-rollRad)
        func aligned(_ pts: [CGPoint]?) -> [CGPoint]? {
            guard let pts else { return nil }
            return pts.map { p in
                let dx = Double(p.x - pivot.x)
                let dy = Double(p.y - pivot.y)
                return CGPoint(x: Double(pivot.x) + dx * cosR - dy * sinR,
                               y: Double(pivot.y) + dx * sinR + dy * cosR)
            }
        }

        let alLeftEye = aligned(face.landmarks?.leftEye?.normalizedPoints)
        let alRightEye = aligned(face.landmarks?.rightEye?.normalizedPoints)
        let alOuterLips = aligned(face.landmarks?.outerLips?.normalizedPoints)
        let alInnerLips = aligned(face.landmarks?.innerLips?.normalizedPoints)
        let alLeftBrow = aligned(face.landmarks?.leftEyebrow?.normalizedPoints)
        let alRightBrow = aligned(face.landmarks?.rightEyebrow?.normalizedPoints)
        let alLeftPupil = aligned(face.landmarks?.leftPupil?.normalizedPoints)
        let alRightPupil = aligned(face.landmarks?.rightPupil?.normalizedPoints)

        var rawPitch = 0.0
        if let pitchNum = face.pitch {
            rawPitch = pitchNum.doubleValue * radToDeg * 1.55
        } else if let lEye = alLeftEye, !lEye.isEmpty,
                  let rEye = alRightEye, !rEye.isEmpty,
                  let lips = alOuterLips, !lips.isEmpty {
            let eyeY = (lEye.map { Double($0.y) }.reduce(0, +) / Double(lEye.count)
                        + rEye.map { Double($0.y) }.reduce(0, +) / Double(rEye.count)) * 0.5
            let mouthY = lips.map { Double($0.y) }.reduce(0, +) / Double(lips.count)
            rawPitch = (((eyeY - mouthY) - 0.28) / 0.14) * 25.0
        }

        var rawMouthRatio = 0.08
        var rawSignedSmile = 0.0
        var mouthX = 0.0
        if let outer = alOuterLips, outer.count >= 6 {
            let xs = outer.map { Double($0.x) }
            let ys = outer.map { Double($0.y) }
            let minX = xs.min() ?? 0.5
            let maxX = xs.max() ?? 0.5
            let w = max(0.05, maxX - minX)
            let h = (ys.max() ?? 0) - (ys.min() ?? 0)
            let yawRef = max(w, eyeSpan * 0.62, 0.14)

            if let inner = alInnerLips, inner.count >= 4 {
                let innerYs = inner.map { Double($0.y) }
                rawMouthRatio = ((innerYs.max() ?? 0) - (innerYs.min() ?? 0)) / yawRef
            } else {
                rawMouthRatio = max(0.0, (h / yawRef) - 0.12)
            }

            mouthX = max(-1.0, min(1.0, (((minX + maxX) * 0.5 - Double(pivot.x)) / eyeSpan) * 4.5))
            if let minIdx = xs.indices.min(by: { xs[$0] < xs[$1] }),
               let maxIdx = xs.indices.max(by: { xs[$0] < xs[$1] }) {
                let cornerAvgY = (ys[minIdx] + ys[maxIdx]) * 0.5
                let midY = ((ys.max() ?? 0) + (ys.min() ?? 0)) * 0.5
                rawSignedSmile = max(-1.0, min(1.0, (cornerAvgY - midY) / w * 5.2))
            }
        }

        func eyeOpenRatio(_ pts: [CGPoint]?) -> Double {
            guard let pts, pts.count >= 4 else { return 1.0 }
            let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
            let w = max(0.03, (xs.max() ?? 0) - (xs.min() ?? 0))
            let h = (ys.max() ?? 0) - (ys.min() ?? 0)
            return max(0.0, min(1.0, (h / w - 0.12) / 0.20))
        }
        let eyeL = eyeOpenRatio(alLeftEye)
        let eyeR = eyeOpenRatio(alRightEye)

        func pupilOffset(_ eyePts: [CGPoint]?, _ pupilPts: [CGPoint]?) -> (Double, Double) {
            guard let eyePts, eyePts.count >= 4, let p = pupilPts?.first else { return (0.0, 0.0) }
            let xs = eyePts.map { Double($0.x) }, ys = eyePts.map { Double($0.y) }
            let cx = ((xs.min() ?? 0) + (xs.max() ?? 0)) * 0.5
            let cy = ((ys.min() ?? 0) + (ys.max() ?? 0)) * 0.5
            let hw = max(0.015, ((xs.max() ?? 0) - (xs.min() ?? 0)) * 0.32)
            let hh = max(0.008, ((ys.max() ?? 0) - (ys.min() ?? 0)) * 0.35)
            return (
                max(-1.0, min(1.0, (Double(p.x) - cx) / hw)),
                max(-1.0, min(1.0, (Double(p.y) - cy) / hh))
            )
        }
        let (gxL, gyL) = pupilOffset(alLeftEye, alLeftPupil)
        let (gxR, gyR) = pupilOffset(alRightEye, alRightPupil)
        let gazeX = (gxL + gxR) * 0.5
        let gazeY = (gyL + gyR) * 0.5

        var rawBrowLiftL = browLiftBaseline
        var rawBrowLiftR = browLiftBaseline
        var innerSlopeL = 0.0
        var innerSlopeR = 0.0
        if let lEye = alLeftEye, !lEye.isEmpty,
           let rEye = alRightEye, !rEye.isEmpty,
           let lBrow = alLeftBrow, lBrow.count >= 2,
           let rBrow = alRightBrow, rBrow.count >= 2 {
            let lEyeY = lEye.reduce(0.0) { $0 + Double($1.y) } / Double(lEye.count)
            let rEyeY = rEye.reduce(0.0) { $0 + Double($1.y) } / Double(rEye.count)
            let lBrowY = lBrow.reduce(0.0) { $0 + Double($1.y) } / Double(lBrow.count)
            let rBrowY = rBrow.reduce(0.0) { $0 + Double($1.y) } / Double(rBrow.count)
            rawBrowLiftL = (lBrowY - lEyeY) / eyeSpan
            rawBrowLiftR = (rBrowY - rEyeY) / eyeSpan

            func innerMinusOuter(_ pts: [CGPoint]) -> Double {
                let sorted = pts.sorted { abs(Double($0.x) - Double(pivot.x)) < abs(Double($1.x) - Double(pivot.x)) }
                let k = min(2, sorted.count)
                let innerY = sorted.prefix(k).reduce(0.0) { $0 + Double($1.y) } / Double(k)
                let outerY = sorted.suffix(k).reduce(0.0) { $0 + Double($1.y) } / Double(k)
                return (innerY - outerY) / eyeSpan
            }
            innerSlopeL = innerMinusOuter(lBrow)
            innerSlopeR = innerMinusOuter(rBrow)
        }

        return ParsedFaceMetrics(
            rawYaw: rawYaw,
            rawPitch: rawPitch,
            rawRoll: rawRoll,
            rawPosX: rawPosX,
            rawPosY: rawPosY,
            rawBoxW: rawBoxW,
            rawMouthRatio: rawMouthRatio,
            rawSignedSmile: rawSignedSmile,
            mouthX: mouthX,
            eyeL: eyeL,
            eyeR: eyeR,
            gazeX: gazeX,
            gazeY: gazeY,
            rawBrowLiftL: rawBrowLiftL,
            rawBrowLiftR: rawBrowLiftR,
            innerSlopeL: innerSlopeL,
            innerSlopeR: innerSlopeR,
            confidence: Double(face.confidence)
        )
    }

    private func applyFaceMetrics(_ m: ParsedFaceMetrics, now: CFAbsoluteTime) {
        let rawBrowAvg = (m.rawBrowLiftL + m.rawBrowLiftR) * 0.5
        let innerBrowSlope = (m.innerSlopeL + m.innerSlopeR) * 0.5

        lastRawYawDeg = m.rawYaw
        lastRawPitchDeg = m.rawPitch
        lastRawRollDeg = m.rawRoll
        lastRawPosX = m.rawPosX
        lastRawPosY = m.rawPosY
        lastRawBoxW = m.rawBoxW
        lastRawMouthRatio = m.rawMouthRatio
        lastRawBrowLift = rawBrowAvg
        lastRawSignedSmile = m.rawSignedSmile
        lastFaceTimestamp = now

        // Auto-calibrate per-user neutral baselines across the first 8 stable face frames
        if autoCalibSamples < 8 && abs(m.rawYaw) < 16.0 && abs(m.rawRoll) < 16.0 {
            autoCalibSamples += 1
            autoCalibBrowSum += rawBrowAvg
            autoCalibSmileSum += m.rawSignedSmile
            autoCalibWidthSum += m.rawBoxW
            let n = Double(autoCalibSamples)
            browLiftBaseline = max(0.06, min(0.32, autoCalibBrowSum / n))
            neutralSmileBaseline = max(-0.18, min(0.18, autoCalibSmileSum / n))
            neutralBoxWidth = max(0.12, autoCalibWidthSum / n)
            if autoCalibSamples == 1 {
                neutralPosXOffset = m.rawPosX
                neutralPosYOffset = m.rawPosY
            }
        }

        // Adaptive closed-lip mouth threshold with hysteresis
        if m.rawMouthRatio < adaptiveClosedFloor + 0.04 {
            adaptiveClosedFloor = max(0.04, min(0.18, adaptiveClosedFloor * 0.96 + m.rawMouthRatio * 0.04))
        }
        let pitchMargin = min(0.04, abs(m.rawPitch - neutralPitchOffset) * 0.0012)
        let openThreshold = adaptiveClosedFloor + 0.056 + pitchMargin
        let closeThreshold = adaptiveClosedFloor + 0.032 + pitchMargin

        if mouthIsCurrentlyOpen {
            if m.rawMouthRatio < closeThreshold { mouthIsCurrentlyOpen = false }
        } else {
            if m.rawMouthRatio > openThreshold { mouthIsCurrentlyOpen = true }
        }

        let mouthOpenY: Double
        if mouthIsCurrentlyOpen {
            let excess = max(0.0, m.rawMouthRatio - closeThreshold)
            mouthOpenY = pow(min(1.0, excess / 0.22), 1.18)
        } else {
            mouthOpenY = 0.0
        }

        let calSmile = max(-1.0, min(1.0, m.rawSignedSmile - neutralSmileBaseline))
        var mouthForm = 0.0
        if abs(calSmile) > 0.10 {
            mouthForm = (calSmile - (calSmile > 0 ? 0.10 : -0.10)) / 0.90
        }

        // Continuous VTS brow parameters (-1..1)
        let browDeltaL = m.rawBrowLiftL - browLiftBaseline
        let browDeltaR = m.rawBrowLiftR - browLiftBaseline
        let browDelta = (browDeltaL + browDeltaR) * 0.5
        if !mouthIsCurrentlyOpen && abs(calSmile) < 0.11 && abs(innerBrowSlope) < 0.016 {
            browLiftBaseline = max(0.06, min(0.32, browLiftBaseline * 0.985 + rawBrowAvg * 0.015))
        }
        let browLY = max(-1.0, min(1.0, browDeltaL * 18.0))
        let browRY = max(-1.0, min(1.0, browDeltaR * 18.0))
        let browLAngle = max(-1.0, min(1.0, m.innerSlopeL * 22.0))
        let browRAngle = max(-1.0, min(1.0, m.innerSlopeR * 22.0))

        // Roll-aligned expression classification with crisp 3-frame confirmation
        let avgEyeOpen = (m.eyeL + m.eyeR) * 0.5
        let exprCandidate: String
        if (avgEyeOpen > 0.68 && browDelta > 0.026) || (browDelta > 0.040 && mouthOpenY > 0.22) {
            exprCandidate = "surprised"
        } else if (innerBrowSlope < -0.016 || browDelta < -0.020) && calSmile < 0.12 {
            exprCandidate = "angry"
        } else if calSmile < -0.13 || (calSmile < -0.075 && innerBrowSlope > 0.014) || (calSmile < -0.07 && avgEyeOpen < 0.62) {
            exprCandidate = "sad"
        } else if calSmile > 0.24 || (calSmile > 0.16 && mouthOpenY > 0.14) {
            exprCandidate = "happy"
        } else if calSmile > 0.12 {
            exprCandidate = "warm_smile"
        } else {
            exprCandidate = "neutral"
        }

        if exprCandidate == candidateExpression {
            candidateExprCount += 1
        } else {
            candidateExpression = exprCandidate
            candidateExprCount = 1
        }
        if candidateExprCount >= 3 {
            stableDetectedExpression = exprCandidate
        }

        let calYaw = max(-30.0, min(30.0, m.rawYaw - neutralYawOffset))
        let calPitch = max(-30.0, min(30.0, m.rawPitch - neutralPitchOffset))
        let calRoll = max(-30.0, min(30.0, m.rawRoll - neutralRollOffset))
        let calPosX = max(-10.0, min(10.0, m.rawPosX - neutralPosXOffset))
        let calPosY = max(-10.0, min(10.0, m.rawPosY - neutralPosYOffset))
        let calPosZ = max(-10.0, min(10.0, ((m.rawBoxW - neutralBoxWidth) / max(0.12, neutralBoxWidth)) * 18.0))
        let eyeSmileL = max(0.0, min(1.0, calSmile * 1.45 * (1.15 - m.eyeL * 0.45)))
        let eyeSmileR = max(0.0, min(1.0, calSmile * 1.45 * (1.15 - m.eyeR * 0.45)))
        let cheekPuff = max(0.0, min(1.0, calSmile > 0.16 ? (calSmile - 0.16) * 2.1 : 0.0))

        latestSample.angleX = calYaw
        latestSample.angleY = calPitch
        latestSample.angleZ = calRoll
        latestSample.facePositionX = calPosX
        latestSample.facePositionY = calPosY
        latestSample.facePositionZ = calPosZ
        latestSample.mouthOpenY = mouthOpenY
        latestSample.mouthForm = mouthForm
        latestSample.mouthX = m.mouthX
        latestSample.cheekPuff = cheekPuff
        latestSample.eyeLOpen = m.eyeL
        latestSample.eyeROpen = m.eyeR
        latestSample.eyeSmileL = eyeSmileL
        latestSample.eyeSmileR = eyeSmileR
        latestSample.eyeLeftX = m.gazeX
        latestSample.eyeLeftY = m.gazeY
        latestSample.eyeRightX = m.gazeX
        latestSample.eyeRightY = m.gazeY
        latestSample.browLeftY = browLY
        latestSample.browRightY = browRY
        latestSample.browLeftAngle = browLAngle
        latestSample.browRightAngle = browRAngle
        latestSample.confidence = m.confidence
        latestSample.isFaceDetected = true
        latestSample.detectedExpression = stableDetectedExpression
    }

    private func clearFaceFields() {
        latestSample.isFaceDetected = false
        latestSample.confidence = 0.0
    }

    // MARK: - Dual-Hand 5-Finger Apple Vision Analysis

    private func parseHandsResult(
        _ observations: [VNHumanHandPoseObservation],
        mirror: Bool
    ) -> (left: HandTrackingSample?, right: HandTrackingSample?, distance: Double) {
        let valid = observations.filter { $0.confidence >= 0.25 }
        guard !valid.isEmpty else { return (nil, nil, 0.0) }

        struct ExtractedHand {
            var sample: HandTrackingSample
            var wristPoint: CGPoint
            var isRightScreenSide: Bool
            var obsChirality: VNChirality
        }

        var extracted: [ExtractedHand] = []
        for obs in valid {
            guard let pts = try? obs.recognizedPoints(.all),
                  let wrist = pts[.wrist], wrist.confidence > 0.25 else { continue }

            func pt(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                guard let p = pts[joint], p.confidence > 0.2 else { return nil }
                return p.location
            }
            func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
                hypot(Double(a.x - b.x), Double(a.y - b.y))
            }

            let middleMCP = pt(.middleMCP) ?? pt(.indexMCP) ?? pt(.ringMCP)
            let indexMCP = pt(.indexMCP)
            let pinkyMCP = pt(.littleMCP)

            // Reference palm span makes finger extension invariant to camera distance
            let palmHeight = middleMCP.map { dist(wrist.location, $0) } ?? 0.08
            let palmWidth = (indexMCP != nil && pinkyMCP != nil) ? dist(indexMCP!, pinkyMCP!) : palmHeight * 0.85
            let refSpan = max(0.025, palmHeight, palmWidth)

            func fingerExtension(
                mcp: VNHumanHandPoseObservation.JointName,
                pip: VNHumanHandPoseObservation.JointName,
                dip: VNHumanHandPoseObservation.JointName,
                tip: VNHumanHandPoseObservation.JointName
            ) -> Double {
                guard let pM = pt(mcp), let pT = pt(tip) else { return 0.65 }
                let reachRatio = dist(wrist.location, pT) / max(1e-4, dist(wrist.location, pM))
                let reachNorm = max(0.0, min(1.0, (reachRatio - 0.85) / 0.95))

                if let pP = pt(pip), let pD = pt(dip) {
                    let v1 = CGPoint(x: pP.x - pM.x, y: pP.y - pM.y)
                    let v2 = CGPoint(x: pD.x - pP.x, y: pD.y - pP.y)
                    let v3 = CGPoint(x: pT.x - pD.x, y: pT.y - pD.y)
                    func cosSim(_ a: CGPoint, _ b: CGPoint) -> Double {
                        let na = hypot(Double(a.x), Double(a.y))
                        let nb = hypot(Double(b.x), Double(b.y))
                        guard na > 1e-5, nb > 1e-5 else { return 1.0 }
                        return (Double(a.x) * Double(b.x) + Double(a.y) * Double(b.y)) / (na * nb)
                    }
                    let c1 = cosSim(v1, v2)
                    let c2 = cosSim(v2, v3)
                    let angleScore = max(0.0, min(1.0, ((c1 + c2) * 0.5 + 0.15) / 1.05))
                    return max(0.0, min(1.0, angleScore * 0.58 + reachNorm * 0.42))
                }
                return reachNorm
            }

            func thumbExtension() -> Double {
                guard let tTip = pt(.thumbTip) else { return 0.65 }
                let palmRef = indexMCP ?? middleMCP ?? wrist.location
                let abduction = dist(tTip, palmRef) / refSpan
                let abductScore = max(0.0, min(1.0, (abduction - 0.48) / 0.65))
                if let tCMC = pt(.thumbCMC), let tMP = pt(.thumbMP), let tIP = pt(.thumbIP) {
                    let v1 = CGPoint(x: tMP.x - tCMC.x, y: tMP.y - tCMC.y)
                    let v2 = CGPoint(x: tIP.x - tMP.x, y: tIP.y - tMP.y)
                    let v3 = CGPoint(x: tTip.x - tIP.x, y: tTip.y - tIP.y)
                    let n1 = hypot(Double(v1.x), Double(v1.y)), n2 = hypot(Double(v2.x), Double(v2.y)), n3 = hypot(Double(v3.x), Double(v3.y))
                    if n1 > 1e-5, n2 > 1e-5, n3 > 1e-5 {
                        let c1 = (Double(v1.x * v2.x + v1.y * v2.y)) / (n1 * n2)
                        let c2 = (Double(v2.x * v3.x + v2.y * v3.y)) / (n2 * n3)
                        let straightScore = max(0.0, min(1.0, ((c1 + c2) * 0.5 - 0.35) / 0.60))
                        return max(0.0, min(1.0, abductScore * 0.65 + straightScore * 0.35))
                    }
                }
                return abductScore
            }

            let fThumb = thumbExtension()
            let fIndex = fingerExtension(mcp: .indexMCP, pip: .indexPIP, dip: .indexDIP, tip: .indexTip)
            let fMiddle = fingerExtension(mcp: .middleMCP, pip: .middlePIP, dip: .middleDIP, tip: .middleTip)
            let fRing = fingerExtension(mcp: .ringMCP, pip: .ringPIP, dip: .ringDIP, tip: .ringTip)
            let fPinky = fingerExtension(mcp: .littleMCP, pip: .littlePIP, dip: .littleDIP, tip: .littleTip)
            let overallOpen = fThumb * 0.15 + fIndex * 0.25 + fMiddle * 0.25 + fRing * 0.20 + fPinky * 0.15

            var palmRollDeg = 0.0
            if let mMCP = middleMCP {
                let dx = Double(mMCP.x - wrist.location.x)
                let dy = Double(mMCP.y - wrist.location.y)
                palmRollDeg = atan2(dx, dy) * 180.0 / Double.pi
            }

            let gesture: String?
            if fThumb > 0.66 && fIndex < 0.42 && fMiddle < 0.42 && fRing < 0.42 && fPinky < 0.42 {
                gesture = "thumbs_up"
            } else if fIndex > 0.66 && fMiddle > 0.66 && fRing < 0.46 && fPinky < 0.46 {
                gesture = "peace"
            } else if fIndex > 0.68 && fMiddle < 0.42 && fRing < 0.42 && fPinky < 0.42 {
                gesture = "point"
            } else if fIndex < 0.34 && fMiddle < 0.34 && fRing < 0.34 && fPinky < 0.34 && fThumb < 0.46 {
                gesture = "fist"
            } else if fIndex > 0.66 && fMiddle > 0.66 && fRing > 0.60 && fPinky > 0.58 {
                gesture = "open"
            } else {
                gesture = nil
            }

            let posX = max(-10.0, min(10.0, (Double(wrist.location.x) - 0.5) * 18.0))
            let posY = max(-10.0, min(10.0, ((Double(wrist.location.y) - 0.35) / 0.45) * 10.0 - 2.0))
            let posZ = max(-10.0, min(10.0, ((palmHeight - 0.12) / 0.12) * 5.0))

            let sample = HandTrackingSample(
                found: true,
                confidence: Double(obs.confidence),
                posX: posX,
                posY: posY,
                posZ: posZ,
                angleZ: max(-180.0, min(180.0, palmRollDeg)),
                open: overallOpen,
                thumb: fThumb,
                index: fIndex,
                middle: fMiddle,
                ring: fRing,
                pinky: fPinky,
                detectedGesture: gesture
            )
            extracted.append(ExtractedHand(
                sample: sample,
                wristPoint: wrist.location,
                isRightScreenSide: wrist.location.x >= 0.5,
                obsChirality: obs.chirality
            ))
        }

        if extracted.count >= 2 {
            let sorted = extracted.sorted { $0.wristPoint.x < $1.wristPoint.x }
            let screenLeft = sorted.first!
            let screenRight = sorted.last!
            let distVal = min(10.0, hypot(Double(screenLeft.wristPoint.x - screenRight.wristPoint.x),
                                           Double(screenLeft.wristPoint.y - screenRight.wristPoint.y)) * 12.0)
            if mirror {
                return (screenLeft.sample, screenRight.sample, distVal)
            } else {
                return (screenRight.sample, screenLeft.sample, distVal)
            }
        } else if let single = extracted.first {
            let assignLeft: Bool
            if single.wristPoint.x < 0.45 {
                assignLeft = mirror
            } else if single.wristPoint.x > 0.55 {
                assignLeft = !mirror
            } else {
                assignLeft = (single.obsChirality == .left) ? mirror : !mirror
            }
            return assignLeft ? (single.sample, nil, 0.0) : (nil, single.sample, 0.0)
        }
        return (nil, nil, 0.0)
    }
}
