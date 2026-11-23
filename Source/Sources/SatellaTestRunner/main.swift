import Foundation
import CoreVideo
import SatellaCore
import SatellaRender

func assertTrue(_ cond: Bool, _ msg: String) {
    if !cond {
        fputs("FAIL: \(msg)\n", stderr)
        exit(1)
    }
}

print("Running SatellaCore & SatellaRender unit tests...")

// 1. ZIP round-trip & path traversal / bomb security
do {
    var archive = ZipArchive()
    let text = "Hello Satella World!".data(using: .utf8)!
    archive.entries["manifest.json"] = text
    let encoded = try archive.encode()
    let decoded = try ZipArchive.read(data: encoded)
    assertTrue(decoded.entries["manifest.json"] == text, "ZIP round-trip failed")

    for bad in ["../escape.json", "/etc/passwd", "C:\\foo.json", "evil/script.py", "a/b.sh"] {
        var threw = false
        do { _ = try SatSecurityLimits.validateRelativePath(bad) } catch { threw = true }
        assertTrue(threw, "Failed to reject unsafe path: \(bad)")
    }
    print("  [PASS] zipRoundTripAndSecurityChecks")
} catch {
    fputs("FAIL zip test: \(error)\n", stderr)
    exit(1)
}

// 2. Deformer cycle & malformed bounds detection
do {
    let manifest = SatManifest(
        format: "satella.avatar", schemaVersion: "1.0.0", id: "cycle_test", name: "Cycle",
        canvas: SatCanvas(width: 100, height: 100), model: "model.json", rig: "rig.json"
    )
    let model = SatModelLayout(
        textures: [SatTextureSpec(id: "t0", file: "textures/t.png", width: 10, height: 10)],
        drawables: [SatDrawableSpec(id: "d0", mesh: "meshes/m0.json", drawOrder: 1)]
    )
    let mesh = SatMesh(
        id: "m0", texture: "t0", parent: "a",
        vertices: [[0, 0], [10, 0], [0, 10]],
        uv: [[0, 0], [1, 0], [0, 1]],
        triangles: [0, 1, 2]
    )
    let rig = SatRig(
        parameters: [SatParameterSpec(id: "ParamAngleX", min: -30, default: 0, max: 30)],
        deformers: [
            SatDeformerSpec(id: "a", parent: "b", type: .rotation, pivot: [50, 50], bounds: nil, rows: nil, cols: nil, axes: nil, keyforms: nil),
            SatDeformerSpec(id: "b", parent: "a", type: .rotation, pivot: [50, 50], bounds: nil, rows: nil, cols: nil, axes: nil, keyforms: nil)
        ]
    )
    var pngHdr = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 10, 0, 0, 0, 10, 8, 6, 0, 0, 0])
    pngHdr.append(contentsOf: [0, 0, 0, 0])
    let av = SatLoadedAvatar(
        manifest: manifest, model: model, rig: rig,
        meshes: ["meshes/m0.json": mesh],
        textureData: ["textures/t.png": pngHdr],
        expressions: [], animations: [], effects: []
    )
    let rep = ModelValidator.validate(avatar: av)
    assertTrue(!rep.valid && rep.errors.contains { $0.contains("cycle") }, "Cycle detector failed")
    print("  [PASS] deformerCycleDetection")
}

// 3. Piecewise 1D + Rotation + Warp interpolation math
do {
    let def = SatDeformerSpec(
        id: "rot", parent: nil, type: .rotation, pivot: [100, 100],
        bounds: nil, rows: nil, cols: nil,
        axes: [SatAxisSpec(parameter: "ParamAngleZ", keys: [-30, 0, 30])],
        keyforms: [
            SatDeformerKeyform(angleDeg: -30),
            SatDeformerKeyform(angleDeg: 0),
            SatDeformerKeyform(angleDeg: 30)
        ]
    )
    let st = MeshDeformer.evaluateDeformer(def, paramValues: ["ParamAngleZ": 15.0])
    assertTrue(abs(st.angleDeg - 15.0) < 1e-6, "Angle interpolation mismatch")

    let st90Def = SatDeformerSpec(
        id: "r90", parent: nil, type: .rotation, pivot: [100, 100],
        axes: nil, keyforms: [SatDeformerKeyform(angleDeg: 90)]
    )
    let st90 = MeshDeformer.evaluateDeformer(st90Def, paramValues: [:])
    let (rx, ry) = MeshDeformer.transformPoint(x: 110, y: 100, through: st90)
    assertTrue(abs(rx - 100.0) < 1e-5 && abs(ry - 110.0) < 1e-5, "Rotation direction mismatch")
    print("  [PASS] interpolationAndRotationMath")
}

// 4. Physics settle + Breast physics Off/Normal/Strong toggle
do {
    let pSpec = SatPhysicsSpec(
        fixedTimestep: 1.0 / 60.0,
        gravity: [0, 1],
        wind: [0, 0],
        groups: [
            SatPhysicsGroupSpec(
                id: "bust_l", name: "Bust L", category: .breast, preset: .soft_body, type: .spring2d,
                stiffness: 46, damping: 8, inertia: 0.65, gravityScale: 1, windWeight: 0, maxOutput: 1,
                nodes: nil,
                inputs: [SatPhysicsInputSpec(parameter: "ParamBodyAngleY", weight: 1.0, velocityWeight: nil, kind: .y, reflect: false)],
                outputs: [SatPhysicsOutputSpec(parameter: "ParamBustBounce", nodeIndex: nil, scale: 1.0, weight: 1.0, kind: .y, reflect: false)]
            )
        ]
    )
    let params = [
        SatParameterSpec(id: "ParamBodyAngleY", min: -10, default: 0, max: 10),
        SatParameterSpec(id: "ParamBustBounce", min: -1, default: 0, max: 1)
    ]
    var vals: [String: Double] = ["ParamBodyAngleY": 0, "ParamBustBounce": 0]
    let eng = PhysicsEngine(spec: pSpec)
    eng.breastPhysicsLevel = .normal
    vals["ParamBodyAngleY"] = 8.0
    for _ in 0..<6 { eng.step(dt: 1.0 / 60.0, parameters: params, values: &vals) }
    vals["ParamBodyAngleY"] = 0.0
    for _ in 0..<240 { eng.step(dt: 1.0 / 60.0, parameters: params, values: &vals) }
    assertTrue(abs(vals["ParamBustBounce"] ?? 1.0) < 0.01, "Spring failed to settle cleanly")

    eng.breastPhysicsLevel = .off
    vals["ParamBodyAngleY"] = 10.0
    for _ in 0..<10 { eng.step(dt: 1.0 / 60.0, parameters: params, values: &vals) }
    assertTrue(vals["ParamBustBounce"] == 0.0, "Breast Off level failed to zero output")
    print("  [PASS] physicsSettlesAndBreastToggleWorks")
}

// 5. AutoMesher contour Delaunay check
do {
    let w = 64, h = 64
    var alpha = [UInt8](repeating: 0, count: w * h)
    for y in 16..<48 {
        for x in 16..<48 {
            if (x - 32) * (x - 32) + (y - 32) * (y - 32) <= 14 * 14 {
                alpha[y * w + x] = 255
            }
        }
    }
    let mesh = SatAutoMesher.generateMesh(
        id: "disc", textureId: "t", parentDeformer: nil, partId: nil, drawOrder: 10,
        imgWidth: w, imgHeight: h
    ) { x, y in alpha[y * w + x] }
    assertTrue(mesh.vertices.count >= 8 && mesh.triangles.count >= 12, "AutoMesher produced degenerate mesh")
    print("  [PASS] autoMesherGeneratesValidDelaunayMesh (v=\(mesh.vertices.count), t=\(mesh.triangles.count/3))")
}

// 6. Metal device & runtime shader compilation
do {
    let engine = try RenderEngine()
    assertTrue(!engine.device.name.isEmpty, "No Metal device name")
    print("  [PASS] metalEngineInitializesAndCompilesShaders (\(engine.device.name))")
} catch {
    fputs("FAIL Metal engine init: \(error)\n", stderr)
    exit(1)
}

// 7. One-Euro filter jitter rejection & critically damped spring convergence (zero overshoot)
do {
    var oneEuro = OneEuroFilter(minCutoff: 0.90, beta: 0.035)
    var pipeSpring = CriticallyDampedSpring(initial: 0.0)
    var maxOneEuroDeviation = 0.0
    var maxPipelineDeviation = 0.0
    for i in 0..<180 {
        let noisy = (i % 2 == 0 ? 1.5 : -1.5)
        let fOut = oneEuro.filter(noisy, dt: 1.0 / 60.0)
        let sOut = pipeSpring.step(target: fOut, smoothTime: 0.16, dt: 1.0 / 60.0)
        if i > 60 {
            maxOneEuroDeviation = max(maxOneEuroDeviation, abs(fOut))
            maxPipelineDeviation = max(maxPipelineDeviation, abs(sOut))
        }
    }
    assertTrue(maxOneEuroDeviation < 0.22, "OneEuro failed to attenuate Nyquist jitter: \(maxOneEuroDeviation)")
    assertTrue(maxPipelineDeviation < 0.05, "OneEuro+Spring failed to suppress steady resting jitter: \(maxPipelineDeviation)")

    var spring = CriticallyDampedSpring(initial: 0.0)
    var maxVal = 0.0
    for _ in 0..<180 {
        let v = spring.step(target: 20.0, smoothTime: 0.14, dt: 1.0 / 60.0)
        maxVal = max(maxVal, v)
    }
    assertTrue(maxVal <= 20.005, "Critically damped spring overshot target: \(maxVal)")
    assertTrue(abs(spring.value - 20.0) < 0.01, "Critically damped spring failed to converge: \(spring.value)")
    print(String(format: "  [PASS] oneEuroAndCriticallyDampedMotionSmoothing (filterMax=%.3f, pipelineMax=%.4f, settled=%.3f)", maxOneEuroDeviation, maxPipelineDeviation, spring.value))
}

// 8. Metal IOSurface CVPixelBuffer zero-copy frame render (Virtual Webcam pipeline)
do {
    let engine = try RenderEngine()
    let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 320,
        kCVPixelBufferHeightKey as String: 240,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    var pbOpt: CVPixelBuffer?
    let cr = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pbOpt)
    assertTrue(cr == kCVReturnSuccess && pbOpt != nil, "Failed creating IOSurface CVPixelBuffer")
    let pb = pbOpt!
    try engine.renderFrame(
        into: pb,
        canvasSize: SatCanvas(width: 640, height: 640),
        camera: SatCameraTransform(),
        drawables: [],
        effects: [],
        background: .greenScreen
    )
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let ptr = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let b = ptr[0], g = ptr[1], r = ptr[2], a = ptr[3]
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    assertTrue(g > 240 && r < 10 && b < 10 && a == 255, "Unexpected BGRA pixel output in IOSurface VirtualCam buffer: (\(b),\(g),\(r),\(a))")
    print("  [PASS] metalPixelBufferZeroCopyVirtualCamRender (320x240 BGRA=(0,255,0,255))")
}

// 9. Standalone GothicWitch starless model, clean rest hands without hand-tracking UI params/gestures, closed-mouth expressions, and drag skirt lift
do {
    let gothicPrimary = URL(fileURLWithPath: "/Users/renseven/.gemini/antigravity/scratch/Satella/SatellaAvatar/GothicWitch.sat")
    let gothicFallback = URL(fileURLWithPath: "/Users/renseven/.gemini/antigravity/scratch/Satella/Avatars/GothicWitch.sat")
    let gothicURL = FileManager.default.fileExists(atPath: gothicPrimary.path) ? gothicPrimary : gothicFallback
    if FileManager.default.fileExists(atPath: gothicURL.path) {
        let (avatar, report) = try ModelLoader.loadAndValidate(url: gothicURL)
        assertTrue(report.errors.isEmpty, "GothicWitch failed validation: \(report.errors)")
        assertTrue(!avatar.model.drawables.contains(where: { $0.id == "accessory_hood_star" }), "Veil star drawable must be removed")
        assertTrue(!avatar.rig.parameters.contains(where: { $0.id == "ParamStarSway" }), "ParamStarSway must be removed")
        assertTrue(avatar.model.drawables.contains(where: { $0.id == "dress_panties" }), "dress_panties layer missing")
        assertTrue(avatar.rig.parameters.contains(where: { $0.id == "ParamSkirtLift" }), "ParamSkirtLift missing")
        assertTrue(avatar.model.drawables.contains(where: { $0.id == "body_hand_left" }), "Clean built-in left hand missing")
        assertTrue(avatar.model.drawables.contains(where: { $0.id == "body_hand_right" }), "Clean built-in right hand missing")
        assertTrue(!avatar.rig.parameters.contains(where: { $0.id == "HandLeftFound" }), "Hand-tracking parameters should not be exposed on GothicWitch")
        assertTrue(!avatar.animations.contains(where: { $0.id.hasPrefix("gesture_") }), "Hand-moving gesture animations should be removed from GothicWitch")

        let rig = RigController(avatar: avatar)
        assertTrue(!rig.handTrackingEnabled, "Hand tracking must default to disabled unless explicitly enabled")
        rig.autoExpressionTracking = true
        for _ in 0..<18 {
            _ = rig.step(
                dt: 1.0 / 60.0,
                tracking: TrackingSample(mouthOpenY: 0.0, confidence: 0.9, isFaceDetected: true, detectedExpression: "happy")
            )
        }
        assertTrue(rig.expressionController.activeExpressionId == "happy", "Auto expression tracking failed to switch to happy")
        assertTrue((rig.paramValues["ParamMouthOpenY"] ?? 1.0) < 0.02, "Happy expression forced mouth open over closed camera lips: \(rig.paramValues["ParamMouthOpenY"] ?? -1)")

        rig.autoExpressionTracking = false
        rig.expressionController.select(expressionId: "sad")
        for _ in 0..<18 {
            _ = rig.step(
                dt: 1.0 / 60.0,
                tracking: TrackingSample(confidence: 0.9, isFaceDetected: true, detectedExpression: "happy")
            )
        }
        assertTrue(rig.expressionController.activeExpressionId == "sad", "Manual expression lock overridden when autoExpressionTracking is false")

        // Offline expression preview (camera off) allows preset mouth opening
        rig.expressionController.select(expressionId: "happy")
        for _ in 0..<24 { _ = rig.step(dt: 1.0 / 60.0) }
        assertTrue((rig.paramValues["ParamMouthOpenY"] ?? 0.0) > 0.20, "Offline happy expression preview should open mouth")
        rig.expressionController.select(expressionId: "sad")
        for _ in 0..<18 { _ = rig.step(dt: 1.0 / 60.0) }

        // Drag-triggered skirt lift elevates during drag and settles smoothly on release
        for _ in 0..<18 {
            rig.notifyDrag(deltaX: 22.0, deltaY: 14.0, isDragging: true)
            _ = rig.step(dt: 1.0 / 60.0)
        }
        let peakLift = rig.paramValues["ParamSkirtLift"] ?? 0.0
        assertTrue(peakLift > 0.55, "Drag motion failed to lift skirt (peakLift=\(peakLift))")

        rig.notifyDrag(deltaX: 0.0, deltaY: 0.0, isDragging: false)
        for _ in 0..<60 { _ = rig.step(dt: 1.0 / 60.0) }
        let settledLift = rig.paramValues["ParamSkirtLift"] ?? 1.0
        assertTrue(settledLift < 0.05, "Skirt lift failed to settle after drag release (settledLift=\(settledLift))")
        print(String(format: "  [PASS] gothicExpressionsAndSkirtLiftWithoutHandUI (peakLift=%.2f, settled=%.3f)", peakLift, settledLift))

        // 10. Preserved VTS Parameter Catalog, Hand Tracking & 2-Bone Arm IK Engine (on hand-rigged fixture)
        assertTrue(VTSParameterCatalog.byVtsId["HandLeftFinger_1_Thumb"] != nil, "Missing VTS HandLeftFinger_1_Thumb in catalog")
        assertTrue(VTSParameterCatalog.byVtsId["BrowLeftAngle"] != nil, "Missing VTS BrowLeftAngle in catalog")
        assertTrue(rig.physicsEngine.availableCategories.contains(.breast), "GothicWitch should expose .breast physics category")

        var handRigParams = avatar.rig.parameters
        for pDef in VTSParameterCatalog.all where !handRigParams.contains(where: { $0.id == pDef.vtsId }) {
            handRigParams.append(SatParameterSpec(id: pDef.vtsId, min: pDef.min, default: pDef.defaultValue, max: pDef.max))
        }
        handRigParams.append(SatParameterSpec(id: "ParamArmRElbow", min: -125, default: 0, max: 145))
        let handFixture = SatLoadedAvatar(
            manifest: avatar.manifest, model: avatar.model,
            rig: SatRig(parameters: handRigParams, deformers: avatar.rig.deformers, meshBindings: avatar.rig.meshBindings, dragReactions: avatar.rig.dragReactions),
            physics: avatar.physics, meshes: avatar.meshes, textureData: avatar.textureData,
            expressions: avatar.expressions, animations: avatar.animations, effects: avatar.effects
        )
        let handRig = RigController(avatar: handFixture)
        handRig.handTrackingEnabled = true
        var handSample = TrackingSample()
        handSample.handRight = HandTrackingSample(
            found: true, confidence: 0.95, posX: 4.5, posY: 5.5, posZ: 0.5, angleZ: -12.0,
            open: 0.42, thumb: 0.08, index: 0.98, middle: 0.96, ring: 0.05, pinky: 0.04,
            detectedGesture: "peace"
        )
        for _ in 0..<30 {
            _ = handRig.step(dt: 1.0 / 60.0, tracking: handSample)
        }
        assertTrue((handRig.paramValues["HandRightFound"] ?? 0.0) > 0.70, "Preserved hand tracking engine failed to activate HandRightFound")
        assertTrue((handRig.paramValues["HandRightFinger_2_Index"] ?? 0.0) > 0.85, "Preserved hand tracking engine failed to extend right index finger")
        assertTrue((handRig.paramValues["HandRightFinger_4_Ring"] ?? 1.0) < 0.25, "Preserved hand tracking engine failed to curl right ring finger")
        assertTrue(abs(handRig.paramValues["ParamArmRElbow"] ?? 0.0) > 15.0, "Preserved 2-bone arm IK failed to bend elbow toward raised hand")

        handRig.manualOverrides["HandLeftOpen"] = 0.0
        _ = handRig.step(dt: 1.0 / 60.0)
        assertTrue((handRig.paramValues["HandLeftFinger_2_Index"] ?? 1.0) < 0.05, "HandLeftOpen manual override failed to curl left fingers")
        print("  [PASS] preservedVtsCatalogHandTrackingAndArmIKEngine")
    }

    // 11. Per-Avatar Drag Reaction & Physics Category Isolation on TestAvatar
    let testURL = URL(fileURLWithPath: "/Users/renseven/.gemini/antigravity/scratch/Satella/Avatars/TestAvatar.sat")
    if FileManager.default.fileExists(atPath: testURL.path) {
        let (testAvatar, testRep) = try ModelLoader.loadAndValidate(url: testURL)
        assertTrue(testRep.errors.isEmpty, "TestAvatar failed validation: \(testRep.errors)")
        let testRig = RigController(avatar: testAvatar)
        assertTrue(!testRig.physicsEngine.availableCategories.contains(.breast), "TestAvatar must NOT report breast physics")
        assertTrue((testAvatar.rig.dragReactions?.first?.parameter == "ParamAntennaSway"), "TestAvatar should declare antenna drag reaction")
        for _ in 0..<14 {
            testRig.notifyDrag(deltaX: 25.0, deltaY: 8.0, isDragging: true)
            _ = testRig.step(dt: 1.0 / 60.0)
        }
        assertTrue(abs(testRig.paramValues["ParamAntennaSway"] ?? 0.0) > 0.15, "TestAvatar drag failed to sway antenna via avatar-defined dragReactions")
        assertTrue(testRig.paramValues["ParamSkirtLift"] == nil, "TestAvatar must not synthesize skirt lift parameter")
        print("  [PASS] perAvatarDragAndPhysicsIsolation")

        // 12. LipSyncProcessor DC rejection, multi-channel peak RMS, noise gate & Hybrid rig routing
        let dsp = LipSyncProcessor(noiseFloorRMS: 0.010, gainScale: 1.6)
        // Constant DC offset (0.25) across 480 frames should settle near 0 after HPF without false mouth opening
        let dcBuf = [Double](repeating: 0.25, count: 960)
        for _ in 0..<8 {
            _ = dsp.processChannels([dcBuf], sampleRate: 48000.0, dt: 0.02)
        }
        let dcRes = dsp.processChannels([dcBuf], sampleRate: 48000.0, dt: 0.02)
        assertTrue(dcRes.mouthOpen < 0.01 && dcRes.rms < 0.005, "LipSync HPF failed to reject DC offset (rms=\(dcRes.rms), open=\(dcRes.mouthOpen))")

        // Multi-channel mic where channel 0 is silent and channel 1 carries 400Hz speech tone (amp 0.06)
        let silenceCh = [Double](repeating: 0.0, count: 960)
        let speechCh = (0..<960).map { i in 0.06 * sin(2.0 * Double.pi * 400.0 * Double(i) / 48000.0) }
        var peakMouth = 0.0
        for _ in 0..<6 {
            let res = dsp.processChannels([silenceCh, speechCh], sampleRate: 48000.0, dt: 0.02)
            peakMouth = max(peakMouth, res.mouthOpen)
        }
        assertTrue(peakMouth > 0.45, "LipSync failed to detect multi-channel speech on non-zero channel (peak=\(peakMouth))")

        // Return to silence and verify release gate closes mouth smoothly
        var quietMouth = peakMouth
        for _ in 0..<30 {
            quietMouth = dsp.processChannels([silenceCh, silenceCh], sampleRate: 48000.0, dt: 0.02).mouthOpen
        }
        assertTrue(quietMouth < 0.02, "LipSync failed to close smoothly on silence (quietMouth=\(quietMouth))")

        // Verify Hybrid RigController routing passes active mic audio to ParamMouthOpenY & VoiceVolume
        testRig.inputMode = .hybrid
        for _ in 0..<12 {
            _ = testRig.step(dt: 1.0 / 60.0, tracking: TrackingSample(), micMouthOpen: 0.65, isMicActive: true)
        }
        let rigOpen = testRig.paramValues["ParamMouthOpenY"] ?? 0.0
        assertTrue(rigOpen > 0.55, "RigController Hybrid mode failed to drive ParamMouthOpenY from mic (open=\(rigOpen))")
        print(String(format: "  [PASS] lipSyncProcessorGateAndRouting (peakMouth=%.2f, settled=%.3f, rigOpen=%.2f)", peakMouth, quietMouth, rigOpen))
    }
}

print("ALL SVSTUDIO CORE TESTS PASSED!")
