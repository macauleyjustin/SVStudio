import Foundation

public enum TrackingInputMode: String, Codable, CaseIterable, Sendable {
    case faceTracking = "Face Tracking"
    case microphone = "Microphone"
    case hybrid = "Hybrid"
}

public enum CameraTrackingMode: String, Codable, CaseIterable, Sendable {
    case faceOnly = "Face & Head"
    case faceAndHands = "Face + Hands"
    case handsOnly = "Hands Only"

    public var tracksFace: Bool { self != .handsOnly }
    public var tracksHands: Bool { self != .faceOnly }
}

public struct HandTrackingSample: Sendable, Equatable {
    public var found: Bool = false
    public var confidence: Double = 0.0
    public var posX: Double = 0.0
    public var posY: Double = 0.0
    public var posZ: Double = 0.0
    public var angleZ: Double = 0.0
    public var open: Double = 0.65
    public var thumb: Double = 0.65
    public var index: Double = 0.65
    public var middle: Double = 0.65
    public var ring: Double = 0.65
    public var pinky: Double = 0.65
    public var detectedGesture: String? = nil

    public init(
        found: Bool = false,
        confidence: Double = 0.0,
        posX: Double = 0.0,
        posY: Double = 0.0,
        posZ: Double = 0.0,
        angleZ: Double = 0.0,
        open: Double = 0.65,
        thumb: Double = 0.65,
        index: Double = 0.65,
        middle: Double = 0.65,
        ring: Double = 0.65,
        pinky: Double = 0.65,
        detectedGesture: String? = nil
    ) {
        self.found = found
        self.confidence = confidence
        self.posX = posX
        self.posY = posY
        self.posZ = posZ
        self.angleZ = angleZ
        self.open = open
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.pinky = pinky
        self.detectedGesture = detectedGesture
    }
}

public struct TrackingSample: Sendable {
    public var angleX: Double = 0.0
    public var angleY: Double = 0.0
    public var angleZ: Double = 0.0
    public var facePositionX: Double = 0.0
    public var facePositionY: Double = 0.0
    public var facePositionZ: Double = 0.0
    public var mouthOpenY: Double = 0.0
    public var mouthForm: Double = 0.0
    public var mouthX: Double = 0.0
    public var cheekPuff: Double = 0.0
    public var tongueOut: Double = 0.0
    public var eyeLOpen: Double = 1.0
    public var eyeROpen: Double = 1.0
    public var eyeSmileL: Double = 0.0
    public var eyeSmileR: Double = 0.0
    public var eyeLeftX: Double = 0.0
    public var eyeLeftY: Double = 0.0
    public var eyeRightX: Double = 0.0
    public var eyeRightY: Double = 0.0
    public var browLeftY: Double = 0.0
    public var browRightY: Double = 0.0
    public var browLeftAngle: Double = 0.0
    public var browRightAngle: Double = 0.0
    public var confidence: Double = 0.0
    public var isFaceDetected: Bool = false
    public var detectedExpression: String? = nil
    public var handLeft: HandTrackingSample = HandTrackingSample()
    public var handRight: HandTrackingSample = HandTrackingSample()
    public var handDistance: Double = 0.0

    public init(
        angleX: Double = 0,
        angleY: Double = 0,
        angleZ: Double = 0,
        facePositionX: Double = 0,
        facePositionY: Double = 0,
        facePositionZ: Double = 0,
        mouthOpenY: Double = 0,
        mouthForm: Double = 0,
        mouthX: Double = 0,
        cheekPuff: Double = 0,
        tongueOut: Double = 0,
        eyeLOpen: Double = 1,
        eyeROpen: Double = 1,
        eyeSmileL: Double = 0,
        eyeSmileR: Double = 0,
        eyeLeftX: Double = 0,
        eyeLeftY: Double = 0,
        eyeRightX: Double = 0,
        eyeRightY: Double = 0,
        browLeftY: Double = 0,
        browRightY: Double = 0,
        browLeftAngle: Double = 0,
        browRightAngle: Double = 0,
        confidence: Double = 0,
        isFaceDetected: Bool = false,
        detectedExpression: String? = nil,
        handLeft: HandTrackingSample = HandTrackingSample(),
        handRight: HandTrackingSample = HandTrackingSample(),
        handDistance: Double = 0
    ) {
        self.angleX = angleX
        self.angleY = angleY
        self.angleZ = angleZ
        self.facePositionX = facePositionX
        self.facePositionY = facePositionY
        self.facePositionZ = facePositionZ
        self.mouthOpenY = mouthOpenY
        self.mouthForm = mouthForm
        self.mouthX = mouthX
        self.cheekPuff = cheekPuff
        self.tongueOut = tongueOut
        self.eyeLOpen = eyeLOpen
        self.eyeROpen = eyeROpen
        self.eyeSmileL = eyeSmileL
        self.eyeSmileR = eyeSmileR
        self.eyeLeftX = eyeLeftX
        self.eyeLeftY = eyeLeftY
        self.eyeRightX = eyeRightX
        self.eyeRightY = eyeRightY
        self.browLeftY = browLeftY
        self.browRightY = browRightY
        self.browLeftAngle = browLeftAngle
        self.browRightAngle = browRightAngle
        self.confidence = confidence
        self.isFaceDetected = isFaceDetected
        self.detectedExpression = detectedExpression
        self.handLeft = handLeft
        self.handRight = handRight
        self.handDistance = handDistance
    }
}

/// Adaptive One-Euro low-pass filter eliminating resting micro-jitter while preserving crisp fast motion.
public struct OneEuroFilter: Sendable {
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double
    private var hasState = false
    private var prevX = 0.0
    private var prevDX = 0.0

    public init(minCutoff: Double = 1.4, beta: Double = 0.04, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public mutating func reset(to value: Double = 0.0) {
        hasState = false
        prevX = value
        prevDX = 0.0
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * max(0.01, cutoff))
        return 1.0 / (1.0 + tau / max(1e-4, dt))
    }

    public mutating func filter(_ x: Double, dt: Double) -> Double {
        let clampedDt = max(1e-4, min(0.1, dt))
        if !hasState {
            hasState = true
            prevX = x
            prevDX = 0.0
            return x
        }
        let rawDX = (x - prevX) / clampedDt
        let aD = alpha(cutoff: dCutoff, dt: clampedDt)
        let smoothedDX = prevDX + (rawDX - prevDX) * aD
        prevDX = smoothedDX

        let cutoff = minCutoff + beta * abs(smoothedDX)
        let aX = alpha(cutoff: cutoff, dt: clampedDt)
        let out = prevX + (x - prevX) * aX
        prevX = out
        return out
    }
}

/// Analytical C²-continuous critically damped second-order spring smoother (zero overshoot, smooth between 15–30Hz tracking samples).
public struct CriticallyDampedSpring: Sendable {
    public var value: Double
    public var velocity: Double = 0.0

    public init(initial: Double = 0.0) {
        self.value = initial
    }

    public mutating func reset(to v: Double = 0.0) {
        self.value = v
        self.velocity = 0.0
    }

    public mutating func step(target: Double, smoothTime: Double, dt: Double, maxSpeed: Double = 1000.0) -> Double {
        let st = max(0.015, smoothTime)
        let omega = 2.0 / st
        let x = omega * dt
        let expFactor = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

        var delta = value - target
        let maxDelta = maxSpeed * st
        delta = max(-maxDelta, min(maxDelta, delta))
        let clampedTarget = value - delta

        let temp = (velocity + omega * delta) * dt
        velocity = (velocity - omega * temp) * expFactor
        value = clampedTarget + (delta + temp) * expFactor
        return value
    }
}

public final class ExpressionController {
    private var expressions: [SatExpression] = []
    public private(set) var activeExpressionId: String? = nil
    private var weights: [String: Double] = [:]

    public init(expressions: [SatExpression] = [], defaultId: String? = nil) {
        load(expressions: expressions, defaultId: defaultId)
    }

    public func load(expressions: [SatExpression], defaultId: String? = nil) {
        self.expressions = expressions
        self.weights = [:]
        if let def = defaultId, expressions.contains(where: { $0.id == def }) {
            self.activeExpressionId = def
            self.weights[def] = 1.0
        } else if let first = expressions.first {
            self.activeExpressionId = first.id
            self.weights[first.id] = 1.0
        } else {
            self.activeExpressionId = nil
        }
    }

    public func select(expressionId: String?) {
        self.activeExpressionId = expressionId
    }

    public func supports(expressionId: String) -> Bool {
        expressions.contains { $0.id == expressionId }
    }

    public func apply(dt: Double, values: inout [String: Double], meta: [String: SatParameterSpec]) {
        for exp in expressions {
            let isTarget = (exp.id == activeExpressionId)
            let cur = weights[exp.id] ?? 0.0
            let fadeIn = max(0.05, exp.fadeInSeconds ?? 0.25)
            let fadeOut = max(0.05, exp.fadeOutSeconds ?? 0.25)
            let next: Double
            if isTarget {
                next = min(1.0, cur + dt / fadeIn)
            } else {
                next = max(0.0, cur - dt / fadeOut)
            }
            weights[exp.id] = next
            if next <= 1e-4 { continue }

            for p in exp.parameters {
                guard let m = meta[p.parameter] else { continue }
                let base = values[p.parameter] ?? m.default
                let blended: Double
                switch p.blend {
                case .overwrite:
                    blended = base * (1.0 - next) + p.value * next
                case .add:
                    blended = base + p.value * next
                case .multiply:
                    blended = base * ((1.0 - next) + p.value * next)
                }
                values[p.parameter] = max(m.min, min(m.max, blended))
            }
        }
    }
}

private struct HandRigSmoother: Sendable {
    var posXFilter = OneEuroFilter(minCutoff: 1.4, beta: 0.08)
    var posYFilter = OneEuroFilter(minCutoff: 1.4, beta: 0.08)
    var angleFilter = OneEuroFilter(minCutoff: 1.6, beta: 0.06)

    var springFound = CriticallyDampedSpring(initial: 0.0)
    var springPosX = CriticallyDampedSpring(initial: 0.0)
    var springPosY = CriticallyDampedSpring(initial: 0.0)
    var springPosZ = CriticallyDampedSpring(initial: 0.0)
    var springAngleZ = CriticallyDampedSpring(initial: 0.0)
    var springOpen = CriticallyDampedSpring(initial: 0.65)
    var springThumb = CriticallyDampedSpring(initial: 0.65)
    var springIndex = CriticallyDampedSpring(initial: 0.65)
    var springMiddle = CriticallyDampedSpring(initial: 0.65)
    var springRing = CriticallyDampedSpring(initial: 0.65)
    var springPinky = CriticallyDampedSpring(initial: 0.65)

    mutating func reset() {
        posXFilter.reset(to: 0.0)
        posYFilter.reset(to: 0.0)
        angleFilter.reset(to: 0.0)
        springFound.reset(to: 0.0)
        springPosX.reset(to: 0.0)
        springPosY.reset(to: 0.0)
        springPosZ.reset(to: 0.0)
        springAngleZ.reset(to: 0.0)
        springOpen.reset(to: 0.65)
        springThumb.reset(to: 0.65)
        springIndex.reset(to: 0.65)
        springMiddle.reset(to: 0.65)
        springRing.reset(to: 0.65)
        springPinky.reset(to: 0.65)
    }

    mutating func step(
        sample: HandTrackingSample,
        enabled: Bool,
        sensitivity: Double,
        smoothTime: Double,
        dt: Double
    ) -> (foundWeight: Double, posX: Double, posY: Double, posZ: Double, angleZ: Double, open: Double, thumb: Double, index: Double, middle: Double, ring: Double, pinky: Double) {
        let active = enabled && sample.found && sample.confidence > 0.15
        let foundW = springFound.step(target: active ? 1.0 : 0.0, smoothTime: active ? 0.08 : 0.22, dt: dt, maxSpeed: 20.0)

        let rawX = active ? posXFilter.filter(sample.posX * sensitivity, dt: dt) : posXFilter.filter(0.0, dt: dt)
        let rawY = active ? posYFilter.filter(sample.posY * sensitivity, dt: dt) : posYFilter.filter(0.0, dt: dt)
        let rawA = active ? angleFilter.filter(sample.angleZ, dt: dt) : angleFilter.filter(0.0, dt: dt)

        let pX = springPosX.step(target: rawX, smoothTime: smoothTime, dt: dt, maxSpeed: 90.0)
        let pY = springPosY.step(target: rawY, smoothTime: smoothTime, dt: dt, maxSpeed: 90.0)
        let pZ = springPosZ.step(target: active ? sample.posZ * sensitivity : 0.0, smoothTime: smoothTime * 1.15, dt: dt, maxSpeed: 60.0)
        let ang = springAngleZ.step(target: rawA, smoothTime: smoothTime, dt: dt, maxSpeed: 720.0)

        let fSmooth = max(0.045, smoothTime * 0.65)
        let op = springOpen.step(target: active ? sample.open : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        let th = springThumb.step(target: active ? sample.thumb : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        let ix = springIndex.step(target: active ? sample.index : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        let md = springMiddle.step(target: active ? sample.middle : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        let rg = springRing.step(target: active ? sample.ring : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        let pk = springPinky.step(target: active ? sample.pinky : 0.65, smoothTime: fSmooth, dt: dt, maxSpeed: 14.0)
        return (foundW, pX, pY, pZ, ang, op, th, ix, md, rg, pk)
    }
}

public final class RigController {
    public private(set) var avatar: SatLoadedAvatar
    public private(set) var paramMeta: [String: SatParameterSpec] = [:]
    public private(set) var meshBindingsById: [String: SatMeshBindingSpec] = [:]
    public var paramValues: [String: Double] = [:]
    public var manualOverrides: [String: Double] = [:]

    public let expressionController = ExpressionController()
    public let physicsEngine = PhysicsEngine(spec: nil)
    public let effectsRenderer = EffectsRenderer()

    public var inputMode: TrackingInputMode = .hybrid
    public var faceSensitivity: Double = 1.0
    public var headSmoothing: Double = 0.40
    public var autoExpressionTracking: Bool = true
    public var handTrackingEnabled: Bool = false
    public var handSensitivity: Double = 1.0
    public var handSmoothing: Double = 0.36
    public var dragReactionsEnabled: Bool = true
    public var elapsedTime: Double = 0.0
    public var animationsEnabled: Bool = true
    public var effectsEnabled: Bool = true
    public private(set) var activeGestureId: String? = nil

    // Adaptive One-Euro filters for incoming webcam telemetry
    private var yawOneEuro = OneEuroFilter(minCutoff: 1.05, beta: 0.055)
    private var pitchOneEuro = OneEuroFilter(minCutoff: 1.05, beta: 0.055)
    private var rollOneEuro = OneEuroFilter(minCutoff: 0.95, beta: 0.045)
    private var mouthOpenOneEuro = OneEuroFilter(minCutoff: 3.5, beta: 0.14)
    private var mouthFormOneEuro = OneEuroFilter(minCutoff: 1.6, beta: 0.04)

    // Critically damped display-rate springs for silky C² interpolation at 60/120fps
    private var springHeadX = CriticallyDampedSpring()
    private var springHeadY = CriticallyDampedSpring()
    private var springHeadZ = CriticallyDampedSpring()
    private var springFacePosX = CriticallyDampedSpring()
    private var springFacePosY = CriticallyDampedSpring()
    private var springFacePosZ = CriticallyDampedSpring()
    private var springBodyX = CriticallyDampedSpring()
    private var springBodyY = CriticallyDampedSpring()
    private var springBodyZ = CriticallyDampedSpring()
    private var springMouthOpen = CriticallyDampedSpring()
    private var springMouthForm = CriticallyDampedSpring()
    private var springMouthX = CriticallyDampedSpring()
    private var springCheek = CriticallyDampedSpring()
    private var springTongue = CriticallyDampedSpring()
    private var springEyeL = CriticallyDampedSpring(initial: 1.0)
    private var springEyeR = CriticallyDampedSpring(initial: 1.0)
    private var springEyeSmileL = CriticallyDampedSpring()
    private var springEyeSmileR = CriticallyDampedSpring()
    private var springGazeX = CriticallyDampedSpring()
    private var springGazeY = CriticallyDampedSpring()
    private var springBrowLY = CriticallyDampedSpring()
    private var springBrowRY = CriticallyDampedSpring()
    private var springBrowLAngle = CriticallyDampedSpring()
    private var springBrowRAngle = CriticallyDampedSpring()
    private var springMicOpen = CriticallyDampedSpring()

    // Dual-hand VTS filters & springs + avatar-defined drag reaction springs
    private var leftHandSmoother = HandRigSmoother()
    private var rightHandSmoother = HandRigSmoother()
    private var dragReactionSprings: [String: CriticallyDampedSpring] = [:]

    // Independent hand/arm gesture playback & viewport drag energy states
    private var gestureWeights: [String: Double] = [:]
    private var gestureClock: Double = 0.0
    private var dragSpeed: Double = 0.0
    private var dragDeltaX: Double = 0.0
    private var dragDeltaY: Double = 0.0
    private var isActivelyDragging: Bool = false
    private var dragIdleTimer: Double = 0.0
    private var pendingAutoExpr: String? = nil
    private var pendingAutoExprTime: Double = 0.0

    // Organic idle blink clock for exposed-eye avatars
    private var blinkTimer: Double = 0.0
    private var nextBlinkInterval: Double = 3.8
    private var latestDeformerStates: [String: EvaluatedDeformerState] = [:]

    public init(avatar: SatLoadedAvatar) {
        self.avatar = avatar
        configureAvatar(avatar)
    }

    public func load(avatar: SatLoadedAvatar) {
        self.avatar = avatar
        configureAvatar(avatar)
    }

    private func configureAvatar(_ avatar: SatLoadedAvatar) {
        paramMeta = Dictionary(uniqueKeysWithValues: avatar.rig.parameters.map { ($0.id, $0) })
        paramValues = Dictionary(uniqueKeysWithValues: avatar.rig.parameters.map { ($0.id, $0.default) })
        manualOverrides = [:]
        meshBindingsById = Dictionary(
            (avatar.rig.meshBindings ?? []).map { ($0.meshId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        expressionController.load(
            expressions: avatar.expressions,
            defaultId: avatar.manifest.defaultExpression
        )
        physicsEngine.load(spec: avatar.physics)
        effectsRenderer.load(specs: avatar.effects)

        dragReactionSprings = [:]
        for reaction in avatar.rig.dragReactions ?? [] {
            let rest = reaction.restValue ?? paramMeta[reaction.parameter]?.default ?? 0.0
            dragReactionSprings[reaction.id] = CriticallyDampedSpring(initial: rest)
        }

        elapsedTime = 0.0
        activeGestureId = nil
        gestureWeights = [:]
        gestureClock = 0.0
        dragSpeed = 0.0
        dragDeltaX = 0.0
        dragDeltaY = 0.0
        isActivelyDragging = false
        dragIdleTimer = 0.0
        pendingAutoExpr = nil
        pendingAutoExprTime = 0.0
        resetMotionFilters()
    }

    private func resetMotionFilters() {
        yawOneEuro.reset(to: 0)
        pitchOneEuro.reset(to: 0)
        rollOneEuro.reset(to: 0)
        mouthOpenOneEuro.reset(to: 0)
        mouthFormOneEuro.reset(to: 0)
        springHeadX.reset(to: 0)
        springHeadY.reset(to: 0)
        springHeadZ.reset(to: 0)
        springFacePosX.reset(to: 0)
        springFacePosY.reset(to: 0)
        springFacePosZ.reset(to: 0)
        springBodyX.reset(to: 0)
        springBodyY.reset(to: 0)
        springBodyZ.reset(to: 0)
        springMouthOpen.reset(to: 0)
        springMouthForm.reset(to: 0)
        springMouthX.reset(to: 0)
        springCheek.reset(to: 0)
        springTongue.reset(to: 0)
        springEyeL.reset(to: 1.0)
        springEyeR.reset(to: 1.0)
        springEyeSmileL.reset(to: 0.0)
        springEyeSmileR.reset(to: 0.0)
        springGazeX.reset(to: 0.0)
        springGazeY.reset(to: 0.0)
        springBrowLY.reset(to: 0.0)
        springBrowRY.reset(to: 0.0)
        springBrowLAngle.reset(to: 0.0)
        springBrowRAngle.reset(to: 0.0)
        springMicOpen.reset(to: 0.0)
        leftHandSmoother.reset()
        rightHandSmoother.reset()
        for reaction in avatar.rig.dragReactions ?? [] {
            let rest = reaction.restValue ?? paramMeta[reaction.parameter]?.default ?? 0.0
            dragReactionSprings[reaction.id] = CriticallyDampedSpring(initial: rest)
        }
        blinkTimer = 0.0
    }

    /// Selects or clears an independent arm/hand gesture animation without overriding facial expressions.
    public func selectGesture(_ gestureId: String?) {
        if gestureId != activeGestureId, gestureId != nil {
            gestureClock = 0.0
        }
        activeGestureId = gestureId
    }

    /// Feeds viewport drag motion into avatar-defined drag reaction springs (settles back to rest on release).
    public func notifyDrag(deltaX: Double, deltaY: Double, isDragging: Bool) {
        isActivelyDragging = isDragging
        if isDragging {
            dragIdleTimer = 0.0
            dragSpeed = hypot(deltaX, deltaY)
            dragDeltaX = max(-40.0, min(40.0, dragDeltaX * 0.4 + deltaX))
            dragDeltaY = max(-40.0, min(40.0, dragDeltaY * 0.4 + deltaY))
        } else {
            dragSpeed = 0.0
        }
    }

    public func resetParametersToDefault() {
        for p in avatar.rig.parameters {
            paramValues[p.id] = p.default
        }
        manualOverrides = [:]
        resetMotionFilters()
        physicsEngine.reset()
    }

    /// Deterministic 9-step evaluation order matching SAT_RIGGING_SPEC.md
    public func step(
        dt rawDt: Double,
        tracking: TrackingSample = TrackingSample(),
        micMouthOpen: Double = 0.0,
        isMicActive: Bool = false
    ) -> (drawables: [EvaluatedDrawable], effects: [EffectsRenderGroup]) {
        let dt = max(1e-4, min(0.1, rawDt))
        elapsedTime += dt

        // Step 1 & 2: Reset frame base to defaults, filter & critically-damp tracking + mic inputs
        for p in avatar.rig.parameters {
            paramValues[p.id] = p.default
        }

        // Smooth time range [0.045s .. 0.27s] mapped cleanly from UI headSmoothing [0.05 .. 0.9]
        let headSmoothTime = 0.045 + max(0.05, min(0.95, headSmoothing)) * 0.24
        let bodySmoothTime = headSmoothTime * 1.45 + 0.05

        let hasLiveFace = tracking.isFaceDetected && tracking.confidence > 0.15
        let targetYaw = yawOneEuro.filter(hasLiveFace ? tracking.angleX * faceSensitivity : 0.0, dt: dt)
        let targetPitch = pitchOneEuro.filter(hasLiveFace ? tracking.angleY * faceSensitivity : 0.0, dt: dt)
        let targetRoll = rollOneEuro.filter(hasLiveFace ? tracking.angleZ * faceSensitivity : 0.0, dt: dt)
        let targetFaceMouthOpen = hasLiveFace ? max(0.0, min(1.0, mouthOpenOneEuro.filter(tracking.mouthOpenY, dt: dt))) : 0.0
        let targetFaceMouthForm = hasLiveFace ? max(-1.0, min(1.0, mouthFormOneEuro.filter(tracking.mouthForm, dt: dt))) : 0.0
        let targetEyeL = hasLiveFace ? tracking.eyeLOpen : 1.0
        let targetEyeR = hasLiveFace ? tracking.eyeROpen : 1.0

        let headX = springHeadX.step(target: targetYaw, smoothTime: headSmoothTime, dt: dt, maxSpeed: 280.0)
        let headY = springHeadY.step(target: targetPitch, smoothTime: headSmoothTime, dt: dt, maxSpeed: 260.0)
        let headZ = springHeadZ.step(target: targetRoll, smoothTime: headSmoothTime * 1.06, dt: dt, maxSpeed: 250.0)
        let facePosX = springFacePosX.step(target: hasLiveFace ? tracking.facePositionX * faceSensitivity : 0.0, smoothTime: headSmoothTime * 1.25, dt: dt, maxSpeed: 60.0)
        let facePosY = springFacePosY.step(target: hasLiveFace ? tracking.facePositionY * faceSensitivity : 0.0, smoothTime: headSmoothTime * 1.25, dt: dt, maxSpeed: 60.0)
        let facePosZ = springFacePosZ.step(target: hasLiveFace ? tracking.facePositionZ * faceSensitivity : 0.0, smoothTime: headSmoothTime * 1.25, dt: dt, maxSpeed: 60.0)

        // Torso & shoulders follow head rotation + face translation with natural weight
        let bodyX = springBodyX.step(target: headX * 0.34 + facePosX * 0.65, smoothTime: bodySmoothTime, dt: dt, maxSpeed: 110.0)
        let bodyY = springBodyY.step(target: headY * 0.28 + facePosY * 0.55, smoothTime: bodySmoothTime, dt: dt, maxSpeed: 110.0)
        let bodyZ = springBodyZ.step(target: headZ * 0.28, smoothTime: bodySmoothTime, dt: dt, maxSpeed: 110.0)

        let smoothFaceMouthOpen = springMouthOpen.step(target: targetFaceMouthOpen, smoothTime: 0.055, dt: dt)
        let smoothFaceMouthForm = springMouthForm.step(target: targetFaceMouthForm, smoothTime: 0.11, dt: dt)
        let smoothMouthX = springMouthX.step(target: hasLiveFace ? tracking.mouthX : 0.0, smoothTime: 0.08, dt: dt)
        let smoothCheek = springCheek.step(target: hasLiveFace ? tracking.cheekPuff : 0.0, smoothTime: 0.11, dt: dt)
        let smoothTongue = springTongue.step(target: hasLiveFace ? tracking.tongueOut : 0.0, smoothTime: 0.08, dt: dt)
        let smoothEyeL = springEyeL.step(target: targetEyeL, smoothTime: 0.045, dt: dt)
        let smoothEyeR = springEyeR.step(target: targetEyeR, smoothTime: 0.045, dt: dt)
        let smoothEyeSmileL = springEyeSmileL.step(target: hasLiveFace ? tracking.eyeSmileL : 0.0, smoothTime: 0.10, dt: dt)
        let smoothEyeSmileR = springEyeSmileR.step(target: hasLiveFace ? tracking.eyeSmileR : 0.0, smoothTime: 0.10, dt: dt)
        let smoothGazeX = springGazeX.step(target: hasLiveFace ? (tracking.eyeLeftX + tracking.eyeRightX) * 0.5 : 0.0, smoothTime: 0.075, dt: dt)
        let smoothGazeY = springGazeY.step(target: hasLiveFace ? (tracking.eyeLeftY + tracking.eyeRightY) * 0.5 : 0.0, smoothTime: 0.075, dt: dt)
        let smoothBrowLY = springBrowLY.step(target: hasLiveFace ? tracking.browLeftY : 0.0, smoothTime: 0.085, dt: dt)
        let smoothBrowRY = springBrowRY.step(target: hasLiveFace ? tracking.browRightY : 0.0, smoothTime: 0.085, dt: dt)
        let smoothBrowLAngle = springBrowLAngle.step(target: hasLiveFace ? tracking.browLeftAngle : 0.0, smoothTime: 0.09, dt: dt)
        let smoothBrowRAngle = springBrowRAngle.step(target: hasLiveFace ? tracking.browRightAngle : 0.0, smoothTime: 0.09, dt: dt)
        let clampedMic = max(0.0, min(1.0, micMouthOpen))
        let smoothMicOpen = springMicOpen.step(target: clampedMic, smoothTime: 0.042, dt: dt)

        // Lively organic living idle sway so character always feels alive even at rest
        var idleYaw = 0.0, idlePitch = 0.0, idleRoll = 0.0
        var idleBodyX = 0.0, idleBodyZ = 0.0
        var autoBlink = 1.0
        if animationsEnabled {
            let idleWeight = hasLiveFace ? 0.30 : 1.0
            idleYaw = (sin(elapsedTime * 0.72) * 2.4 + sin(elapsedTime * 0.31) * 1.2) * idleWeight
            idlePitch = (sin(elapsedTime * 0.90 + 0.9) * 1.6) * idleWeight
            idleRoll = (sin(elapsedTime * 0.56 + 1.7) * 2.1) * idleWeight
            idleBodyX = sin(elapsedTime * 0.46 + 0.4) * 1.45 * idleWeight
            idleBodyZ = sin(elapsedTime * 0.40 + 2.1) * 1.15 * idleWeight

            if !hasLiveFace && avatar.manifest.features?.concealedEyes != true {
                blinkTimer += dt
                if blinkTimer >= nextBlinkInterval {
                    let phase = blinkTimer - nextBlinkInterval
                    let blinkDuration = 0.18
                    if phase < blinkDuration {
                        let s = sin((phase / blinkDuration) * Double.pi)
                        autoBlink = 1.0 - s
                    } else {
                        blinkTimer = 0.0
                        nextBlinkInterval = 3.2 + abs(sin(elapsedTime * 1.7)) * 2.4
                    }
                }
            }
        }

        setVTS("FaceAngleX", headX + idleYaw)
        setVTS("FaceAngleY", headY + idlePitch)
        setVTS("FaceAngleZ", headZ + idleRoll)
        setVTS("FacePositionX", facePosX)
        setVTS("FacePositionY", facePosY)
        setVTS("FacePositionZ", facePosZ)
        setVTS("ParamBodyAngleX", bodyX + idleBodyX)
        setVTS("ParamBodyAngleY", bodyY)
        setVTS("ParamBodyAngleZ", bodyZ + idleBodyZ)
        setVTS("VoiceVolume", smoothMicOpen)

        if avatar.manifest.features?.concealedEyes != true {
            setVTS("EyeOpenLeft", hasLiveFace ? smoothEyeL : autoBlink)
            setVTS("EyeOpenRight", hasLiveFace ? smoothEyeR : autoBlink)
            setVTS("EyeLeftX", smoothGazeX)
            setVTS("EyeLeftY", smoothGazeY)
            setVTS("EyeRightX", hasLiveFace ? tracking.eyeRightX : 0.0)
            setVTS("EyeRightY", hasLiveFace ? tracking.eyeRightY : 0.0)
        }

        // Step 3: Evaluate auto-play idle animations, facial expressions, gestures, hand tracking & drag reactions
        if animationsEnabled {
            for (idx, anim) in avatar.animations.enumerated() {
                let auto = idx < (avatar.manifest.animations?.count ?? 0)
                    ? (avatar.manifest.animations?[idx].autoPlay ?? (idx == 0))
                    : (idx == 0)
                if auto {
                    evaluateAnimation(anim, at: elapsedTime)
                }
            }
        }

        if autoExpressionTracking, hasLiveFace, let det = tracking.detectedExpression {
            let resolvedExpr: String?
            if expressionController.supports(expressionId: det) {
                resolvedExpr = det
            } else if det == "warm_smile", expressionController.supports(expressionId: "happy") {
                resolvedExpr = "happy"
            } else if det == "neutral", let def = avatar.manifest.defaultExpression, expressionController.supports(expressionId: def) {
                resolvedExpr = def
            } else {
                resolvedExpr = nil
            }
            if let targetExpr = resolvedExpr {
                if pendingAutoExpr == targetExpr {
                    pendingAutoExprTime += dt
                } else {
                    pendingAutoExpr = targetExpr
                    pendingAutoExprTime = dt
                }
                if pendingAutoExprTime >= 0.08 {
                    expressionController.select(expressionId: targetExpr)
                }
            }
        }
        expressionController.apply(dt: dt, values: &paramValues, meta: paramMeta)

        // Blend triggered arm/hand gestures independently after facial expression layer
        gestureClock += dt
        var inactiveGestures: [SatAnimation] = []
        var activeGestureAnim: SatAnimation? = nil
        var maxGestureWeight = 0.0
        for (idx, anim) in avatar.animations.enumerated() {
            let auto = idx < (avatar.manifest.animations?.count ?? 0)
                ? (avatar.manifest.animations?[idx].autoPlay ?? (idx == 0))
                : (idx == 0)
            if auto { continue }
            let isTarget = (anim.id == activeGestureId)
            let cur = gestureWeights[anim.id] ?? 0.0
            let fadeIn = max(0.05, anim.fadeInSeconds ?? 0.22)
            let fadeOut = max(0.05, anim.fadeOutSeconds ?? 0.22)
            let next = isTarget ? min(1.0, cur + dt / fadeIn) : max(0.0, cur - dt / fadeOut)
            gestureWeights[anim.id] = next
            maxGestureWeight = max(maxGestureWeight, next)
            if next <= 1e-4 { continue }
            if isTarget {
                activeGestureAnim = anim
            } else {
                inactiveGestures.append(anim)
            }
        }
        for anim in inactiveGestures {
            if let w = gestureWeights[anim.id], w > 1e-4 {
                evaluateBlendedAnimation(anim, at: gestureClock, weight: w)
            }
        }
        if let activeGestureAnim, let w = gestureWeights[activeGestureAnim.id], w > 1e-4 {
            evaluateBlendedAnimation(activeGestureAnim, at: gestureClock, weight: w)
        }

        // Dual-hand VTS tracking + analytical 2-bone arm IK (yields gracefully to active gesture presets)
        let handSmoothTime = 0.045 + max(0.05, min(0.95, handSmoothing)) * 0.16
        let leftHandState = leftHandSmoother.step(
            sample: tracking.handLeft,
            enabled: handTrackingEnabled,
            sensitivity: handSensitivity,
            smoothTime: handSmoothTime,
            dt: dt
        )
        let rightHandState = rightHandSmoother.step(
            sample: tracking.handRight,
            enabled: handTrackingEnabled,
            sensitivity: handSensitivity,
            smoothTime: handSmoothTime,
            dt: dt
        )
        let handOverrideSuppress = max(0.0, 1.0 - maxGestureWeight)
        applyHandState(leftHandState, isLeft: true, suppressFactor: handOverrideSuppress)
        applyHandState(rightHandState, isLeft: false, suppressFactor: handOverrideSuppress)
        let dualFound = (leftHandState.foundWeight > 0.2 && rightHandState.foundWeight > 0.2)
            ? min(leftHandState.foundWeight, rightHandState.foundWeight) * handOverrideSuppress
            : 0.0
        setVTS("HandDistance", tracking.handDistance * dualFound)

        // Avatar-defined drag reactions (completely driven by each .sat avatar's `rig.dragReactions`)
        let dragContribs = evaluateDragReactions(dt: dt)
        applyDragContributions(dragContribs)

        // Step 4: Blend continuous VTS face/brow/mouth tracking signals & enforce closed-mouth fidelity
        if hasLiveFace {
            addVTS("BrowLeftY", smoothBrowLY * 0.85)
            addVTS("BrowRightY", smoothBrowRY * 0.85)
            addVTS("BrowLeftAngle", smoothBrowLAngle * 0.85)
            addVTS("BrowRightAngle", smoothBrowRAngle * 0.85)
            setVTS("Brows", (smoothBrowLY + smoothBrowRY) * 0.5)
            addVTS("EyeSmileLeft", smoothEyeSmileL * 0.85)
            addVTS("EyeSmileRight", smoothEyeSmileR * 0.85)
            addVTS("CheekPuff", smoothCheek * 0.80)
            setVTS("MouthX", smoothMouthX)
            setVTS("TongueOut", smoothTongue)
        }

        let resolvedMouthOpen: Double
        switch inputMode {
        case .faceTracking:
            resolvedMouthOpen = hasLiveFace ? smoothFaceMouthOpen : 0.0
        case .microphone:
            resolvedMouthOpen = smoothMicOpen
        case .hybrid:
            if isMicActive {
                if smoothMicOpen > 0.04 {
                    resolvedMouthOpen = max(smoothMicOpen, smoothFaceMouthOpen * 0.40)
                } else {
                    resolvedMouthOpen = smoothFaceMouthOpen > 0.28 ? (smoothFaceMouthOpen - 0.14) : 0.0
                }
            } else {
                resolvedMouthOpen = hasLiveFace ? smoothFaceMouthOpen : 0.0
            }
        }
        let hasLiveMouthInput = (inputMode != .microphone && hasLiveFace) || (inputMode != .faceTracking && isMicActive)
        if hasLiveMouthInput {
            // Live camera or mic owns lip opening so expression presets never force mouth open over closed lips
            setVTS("MouthOpen", resolvedMouthOpen)
        } else {
            let existingOpen = firstParamValue("MouthOpen") ?? 0.0
            setVTS("MouthOpen", max(existingOpen, resolvedMouthOpen))
        }
        if hasLiveFace {
            let curForm = firstParamValue("MouthSmile") ?? 0.0
            setVTS("MouthSmile", curForm + smoothFaceMouthForm * 0.60)
        }

        for (k, v) in manualOverrides {
            setIfExists(k, v)
        }
        // Convenience: manually dragging HandLeftOpen / HandRightOpen opens/closes all 5 fingers unless overridden
        for side in ["Left", "Right"] {
            let openKey = "Hand\(side)Open"
            let legacyKey = side == "Left" ? "ParamHandL" : "ParamHandR"
            if let openVal = manualOverrides[openKey] ?? manualOverrides[legacyKey] {
                for finger in ["1_Thumb", "2_Index", "3_Middle", "4_Ring", "5_Pinky"] {
                    let fKey = "Hand\(side)Finger_\(finger)"
                    if manualOverrides[fKey] == nil {
                        setIfExists(fKey, openVal)
                    }
                }
            }
        }
        clampAll()

        // Step 5: Evaluate keyforms Pass 1
        var deformerStates: [String: EvaluatedDeformerState] = [:]
        for d in avatar.rig.deformers {
            deformerStates[d.id] = MeshDeformer.evaluateDeformer(d, paramValues: paramValues)
        }

        // Step 6: Step fixed-timestep PhysicsEngine
        if avatar.manifest.features?.physics != false {
            physicsEngine.step(dt: dt, parameters: avatar.rig.parameters, values: &paramValues)
            // Preserve active drag sway/lift reactions even when a drag parameter also participates in physics output
            applyDragContributions(dragContribs)
            for (k, v) in manualOverrides {
                setIfExists(k, v)
            }
            clampAll()
        }

        // Step 7: Re-evaluate deformers with physics output updates
        for d in avatar.rig.deformers {
            deformerStates[d.id] = MeshDeformer.evaluateDeformer(d, paramValues: paramValues)
        }
        latestDeformerStates = deformerStates

        // Step 8 & 9: Transform vertices, sort drawables, evaluate effects
        let drawables = MeshDeformer.evaluateAll(
            avatar: avatar,
            deformerStates: deformerStates,
            meshBindingsById: meshBindingsById,
            paramValues: paramValues
        )

        let effects: [EffectsRenderGroup]
        if effectsEnabled && avatar.manifest.features?.effects != false {
            effects = effectsRenderer.step(
                dt: dt,
                paramValues: paramValues,
                deformerStates: deformerStates
            )
        } else {
            effects = []
        }

        return (drawables, effects)
    }

    private func vtsIds(for vtsId: String) -> [String] {
        var ids: [String] = [vtsId]
        if let mapped = VTSParameterCatalog.byVtsId[vtsId]?.live2dIds {
            for id in mapped where !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    private func firstParamValue(_ vtsId: String) -> Double? {
        for id in vtsIds(for: vtsId) {
            if paramMeta[id] != nil {
                return paramValues[id]
            }
        }
        return nil
    }

    private func setVTS(_ vtsId: String, _ value: Double) {
        for id in vtsIds(for: vtsId) {
            setIfExists(id, value)
        }
    }

    private func addVTS(_ vtsId: String, _ delta: Double) {
        for id in vtsIds(for: vtsId) where paramMeta[id] != nil {
            let cur = paramValues[id] ?? paramMeta[id]!.default
            setIfExists(id, cur + delta)
        }
    }

    private func applyHandState(
        _ s: (foundWeight: Double, posX: Double, posY: Double, posZ: Double, angleZ: Double, open: Double, thumb: Double, index: Double, middle: Double, ring: Double, pinky: Double),
        isLeft: Bool,
        suppressFactor: Double
    ) {
        let prefix = isLeft ? "HandLeft" : "HandRight"
        let weight = max(0.0, min(1.0, s.foundWeight * suppressFactor))
        setVTS("\(prefix)Found", weight)
        guard weight > 0.02 else { return }

        let blend = { (vtsKey: String, tracked: Double) in
            let base = self.firstParamValue(vtsKey) ?? (VTSParameterCatalog.byVtsId[vtsKey]?.defaultValue ?? 0.0)
            self.setVTS(vtsKey, base * (1.0 - weight) + tracked * weight)
        }
        blend("\(prefix)PositionX", s.posX)
        blend("\(prefix)PositionY", s.posY)
        blend("\(prefix)PositionZ", s.posZ)
        blend("\(prefix)AngleZ", s.angleZ)
        blend("\(prefix)Open", s.open)
        blend("\(prefix)Finger_1_Thumb", s.thumb)
        blend("\(prefix)Finger_2_Index", s.index)
        blend("\(prefix)Finger_3_Middle", s.middle)
        blend("\(prefix)Finger_4_Ring", s.ring)
        blend("\(prefix)Finger_5_Pinky", s.pinky)

        // Analytical 2-bone arm IK mapping hand XYZ to shoulder, elbow, and wrist rotations
        let (shoulderDeg, elbowDeg, wristDeg) = solveTwoBoneArmIK(
            posX: s.posX,
            posY: s.posY,
            handAngleZ: s.angleZ,
            isLeft: isLeft
        )
        let shoulderId = isLeft ? "ParamArmLShoulder" : "ParamArmRShoulder"
        let elbowId = isLeft ? "ParamArmLElbow" : "ParamArmRElbow"
        let wristId = isLeft ? "ParamArmLWrist" : "ParamArmRWrist"
        let armVtsId = isLeft ? "ParamArmLA" : "ParamArmRA"

        if let m = paramMeta[shoulderId] {
            let cur = paramValues[shoulderId] ?? m.default
            setIfExists(shoulderId, cur * (1.0 - weight) + shoulderDeg * weight)
        } else if let m = paramMeta[armVtsId] {
            let cur = paramValues[armVtsId] ?? m.default
            setIfExists(armVtsId, cur * (1.0 - weight) + shoulderDeg * weight)
        }
        if let m = paramMeta[elbowId] {
            let cur = paramValues[elbowId] ?? m.default
            setIfExists(elbowId, cur * (1.0 - weight) + elbowDeg * weight)
        }
        if let m = paramMeta[wristId] {
            let cur = paramValues[wristId] ?? m.default
            setIfExists(wristId, cur * (1.0 - weight) + wristDeg * weight)
        }
    }

    private func solveTwoBoneArmIK(posX: Double, posY: Double, handAngleZ: Double, isLeft: Bool) -> (Double, Double, Double) {
        // Target offset relative to shoulder in normalized arm reach coordinates (+dx = outward, +dy = downward)
        let sideSign = isLeft ? -1.0 : 1.0
        let normX = max(-1.0, min(1.0, posX / 10.0))
        let normY = max(-1.0, min(1.0, posY / 10.0))

        let outwardX = max(-0.45, min(0.92, 0.30 + (isLeft ? -normX : normX) * 0.58))
        let downwardY = max(-0.48, min(0.92, 0.58 - normY * 0.85))
        let dx = sideSign * outwardX
        let dy = downwardY

        let l1 = 0.58
        let l2 = 0.42
        let dist = max(0.24, min(0.97, hypot(dx, dy)))

        let cosAlpha = max(-0.98, min(0.98, (dist * dist + l1 * l1 - l2 * l2) / (2.0 * dist * l1)))
        let alpha = acos(cosAlpha)
        let cosBeta = max(-0.98, min(0.98, (dist * dist - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)))
        let bend = acos(cosBeta)

        // Screen-space angle measured from straight down (0, +1): CW (+deg) swings left outward; CCW (-deg) swings right outward
        let thetaTarget = atan2(-dx, dy)
        let degPerRad = 180.0 / Double.pi
        let sA = thetaTarget - alpha
        let sB = thetaTarget + alpha
        // Pick the lower-elbow IK branch (max cos(shoulderWorld)) so elbows stay anatomically downward
        let chooseA = cos(sA) >= cos(sB)
        let shoulderWorldDeg = (chooseA ? sA : sB) * degPerRad
        let elbowDeg = (chooseA ? bend : -bend) * degPerRad * 0.92
        let restOffset = isLeft ? 15.0 : -15.0
        let relShoulder = shoulderWorldDeg - restOffset
        let wristLocal = max(-45.0, min(45.0, handAngleZ - (relShoulder + elbowDeg)))
        if isLeft {
            return (max(-35.0, min(65.0, relShoulder)), max(-135.0, min(125.0, elbowDeg)), wristLocal)
        } else {
            return (max(-65.0, min(35.0, relShoulder)), max(-125.0, min(135.0, elbowDeg)), wristLocal)
        }
    }

    private func evaluateDragReactions(dt: Double) -> [(SatDragReactionSpec, Double, Double)] {
        if isActivelyDragging {
            dragIdleTimer += dt
            if dragIdleTimer > 0.28 {
                isActivelyDragging = false
                dragSpeed = 0.0
            }
        } else {
            dragSpeed = 0.0
        }

        var contributions: [(SatDragReactionSpec, Double, Double)] = []
        let reactions = avatar.rig.dragReactions ?? []
        if !reactions.isEmpty {
            for reaction in reactions {
                let m = paramMeta[reaction.parameter]
                let rest = reaction.restValue ?? m?.default ?? 0.0
                let sens = reaction.sensitivity ?? 1.0
                var target = rest

                if dragReactionsEnabled && isActivelyDragging {
                    switch reaction.trigger {
                    case .move:
                        let factor = min(1.0, max(0.75, (0.78 + dragSpeed * 0.02) * sens))
                        target = rest + (reaction.targetValue - rest) * factor
                    case .shake:
                        let factor = min(1.0, max(0.0, (dragSpeed * 0.045) * sens))
                        target = rest + (reaction.targetValue - rest) * factor
                    case .dragUp:
                        let factor = min(1.0, max(0.0, (-dragDeltaY * 0.04) * sens))
                        target = rest + (reaction.targetValue - rest) * factor
                    case .dragDown:
                        let factor = min(1.0, max(0.0, (dragDeltaY * 0.04) * sens))
                        target = rest + (reaction.targetValue - rest) * factor
                    case .dragHorizontal:
                        let normX = max(-1.0, min(1.0, (-dragDeltaX * 0.045) * sens))
                        target = rest + (reaction.targetValue - rest) * normX
                    }
                }

                var spring = dragReactionSprings[reaction.id] ?? CriticallyDampedSpring(initial: rest)
                let smoothTime = dragReactionsEnabled && isActivelyDragging ? (reaction.attackSeconds ?? 0.08) : (reaction.releaseSeconds ?? 0.16)
                let val = spring.step(target: target, smoothTime: smoothTime, dt: dt, maxSpeed: 18.0)
                dragReactionSprings[reaction.id] = spring

                if abs(val - rest) > 1e-4 {
                    contributions.append((reaction, rest, val))
                }
            }
        }
        dragDeltaX *= exp(-7.5 * dt)
        dragDeltaY *= exp(-7.5 * dt)
        return contributions
    }

    private func applyDragContributions(_ contributions: [(SatDragReactionSpec, Double, Double)]) {
        for (reaction, rest, val) in contributions {
            if reaction.trigger == .dragHorizontal {
                let cur = paramValues[reaction.parameter] ?? rest
                setIfExists(reaction.parameter, cur + (val - rest))
            } else if reaction.targetValue >= rest {
                setIfExists(reaction.parameter, max(paramValues[reaction.parameter] ?? rest, val))
            } else {
                setIfExists(reaction.parameter, min(paramValues[reaction.parameter] ?? rest, val))
            }
        }
    }

    private func setIfExists(_ id: String, _ value: Double) {
        guard let m = paramMeta[id] else { return }
        paramValues[id] = max(m.min, min(m.max, value))
    }

    private func clampAll() {
        for p in avatar.rig.parameters {
            let v = paramValues[p.id] ?? p.default
            paramValues[p.id] = max(p.min, min(p.max, v))
        }
    }

    private func evaluateAnimation(_ anim: SatAnimation, at time: Double) {
        let dur = max(1e-4, anim.duration)
        let shouldLoop = anim.loop ?? true
        let t = shouldLoop ? time.truncatingRemainder(dividingBy: dur) : min(dur, time)

        for track in anim.tracks {
            guard let m = paramMeta[track.parameter], !track.keyframes.isEmpty else { continue }
            let val = sampleTrack(track, at: t)
            let cur = paramValues[track.parameter] ?? m.default
            let next: Double
            switch track.blend ?? .overwrite {
            case .overwrite: next = val
            case .add: next = cur + val
            case .multiply: next = cur * val
            }
            paramValues[track.parameter] = max(m.min, min(m.max, next))
        }
    }

    private func evaluateBlendedAnimation(_ anim: SatAnimation, at time: Double, weight: Double) {
        let dur = max(1e-4, anim.duration)
        let shouldLoop = anim.loop ?? true
        let t = shouldLoop ? time.truncatingRemainder(dividingBy: dur) : min(dur, time)

        for track in anim.tracks {
            guard let m = paramMeta[track.parameter], !track.keyframes.isEmpty else { continue }
            let val = sampleTrack(track, at: t)
            let cur = paramValues[track.parameter] ?? m.default
            if track.interpolation == .stepped {
                if weight >= 0.45 {
                    paramValues[track.parameter] = max(m.min, min(m.max, val))
                }
                continue
            }
            let next: Double
            switch track.blend ?? .overwrite {
            case .overwrite: next = cur * (1.0 - weight) + val * weight
            case .add: next = cur + val * weight
            case .multiply: next = cur * ((1.0 - weight) + val * weight)
            }
            paramValues[track.parameter] = max(m.min, min(m.max, next))
        }
    }

    private func sampleTrack(_ track: SatAnimationTrack, at t: Double) -> Double {
        let kfs = track.keyframes
        if kfs.count == 1 || t <= kfs[0].time {
            return kfs[0].value
        }
        if t >= kfs[kfs.count - 1].time {
            return kfs[kfs.count - 1].value
        }
        var hi = 1
        while hi < kfs.count && kfs[hi].time < t {
            hi += 1
        }
        let a = kfs[hi - 1]
        let b = kfs[hi]
        let span = max(1e-6, b.time - a.time)
        let u = (t - a.time) / span
        switch track.interpolation ?? .linear {
        case .stepped:
            return a.value
        case .linear:
            return a.value + (b.value - a.value) * u
        case .smooth:
            let s = u * u * (3.0 - 2.0 * u)
            return a.value + (b.value - a.value) * s
        }
    }
}
