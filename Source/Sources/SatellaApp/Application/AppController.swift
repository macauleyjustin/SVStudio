import Foundation
import AppKit
import SwiftUI
import Observation
import SatellaCore
import SatellaRender

private final class WebcamSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: LiveRenderSnapshot? = nil

    func set(_ snap: LiveRenderSnapshot?) {
        lock.lock()
        snapshot = snap
        lock.unlock()
    }

    func get() -> LiveRenderSnapshot? {
        lock.lock()
        let out = snapshot
        lock.unlock()
        return out
    }
}

@Observable
@MainActor
public final class AppController: FrameSnapshotProvider {
    public let preferencesStore: PreferencesStore
    public let renderEngine: RenderEngine?
    public let faceTracker = FaceTracker()
    public let lipSync = LipSyncEngine()
    public let virtualWebcam = VirtualWebcamManager()
    private var obsWindowController: OBSCleanWindowController?

    // Avatar State
    public var loadedAvatar: SatLoadedAvatar?
    public var loadedAvatarURL: URL?
    public var validationReport: SatValidationReport?
    public var rigController: RigController?
    public var libraryEntries: [AvatarLibraryEntry] = []

    // View & Output
    public var camera = SatCameraTransform()
    public var backgroundMode: SatBackgroundMode = .black
    public var customBackgroundColor = Color(red: 0.06, green: 0.05, blue: 0.10)
    public var obsBackgroundMode: SatBackgroundMode = .greenScreen
    public var obsCustomColor = Color(red: 0.0, green: 1.0, blue: 0.0)
    public var obsWindowOpen: Bool = false
    public var virtualWebcamEnabled: Bool = false
    public var virtualWebcamBackground: SatBackgroundMode = .black
    public var virtualWebcamFPS: Double = 30.0
    public var availableWebcamSinks: [VirtualWebcamSinkInfo] = []
    public var selectedWebcamSinkID: String? = nil
    public var virtualWebcamStatus: VirtualWebcamStatus = .stopped
    public var virtualWebcamNote: String? = nil
    public var sidebarCollapsed: Bool = false
    public var alwaysOnTop: Bool = false

    // Tracking & Expression Controls
    public var inputMode: TrackingInputMode = .hybrid
    public var cameraTrackingMode: CameraTrackingMode = .faceOnly
    public var faceTrackingEnabled: Bool = false
    public var handTrackingEnabled: Bool = false
    public var mirrorHands: Bool = true
    public var micLipSyncEnabled: Bool = false
    public var faceSensitivity: Double = 1.0
    public var headSmoothing: Double = 0.45
    public var handSensitivity: Double = 1.0
    public var handSmoothing: Double = 0.36
    public var autoExpressionTracking: Bool = true
    public var lipSyncGain: Double = 1.6
    public var lipSyncThreshold: Double = 0.032

    // Rigging / Physics / Drag / Visual FX
    public var activeExpressionId: String? = nil
    public var activeGestureId: String? = nil
    public var physicsEnabled: Bool = true
    public var physicsIntensity: Double = 1.0
    public var breastPhysicsLevel: BreastPhysicsLevel = .normal
    public var categoryPhysicsMultipliers: [SatPhysicsCategory: Double] = [:]
    public var dragReactionsEnabled: Bool = true
    public var animationsEnabled: Bool = true
    public var effectsEnabled: Bool = true

    // Devices & Live Telemetry
    public var availableCameras: [CameraDeviceInfo] = []
    public var selectedCameraID: String? = nil
    public var availableMics: [AudioInputDeviceInfo] = []
    public var selectedMicID: String? = nil
    public var faceTrackerStatus: FaceTrackerStatus = .inactive
    public var lipSyncStatus: LipSyncStatus = .inactive
    public var liveMicLevel: Double = 0.0
    public var liveTrackingSample = TrackingSample()
    public var fpsDisplay: Double = 60.0
    public var frameMsDisplay: Double = 0.0
    public var showValidationDetails: Bool = false
    public var showParameterTestDrawer: Bool = false
    public var paramFilterCategory: Int = 0
    public var calibrationExpanded: Bool = false
    public var selectedInspectorTab: Int = 0
    public var errorMessage: String? = nil

    // Evaluated Frame State
    private var currentDrawables: [EvaluatedDrawable] = []
    private var currentEffects: [EffectsRenderGroup] = []
    private let webcamSnapshotBox = WebcamSnapshotBox()
    private var lastSimTime: CFTimeInterval = CACurrentMediaTime()
    private var lastTelemetrySyncTime: CFTimeInterval = 0.0

    public init(preferencesStore: PreferencesStore = PreferencesStore()) {
        self.preferencesStore = preferencesStore
        do {
            let engine = try RenderEngine()
            self.renderEngine = engine
        } catch {
            self.renderEngine = nil
            self.errorMessage = "Metal initialization failed: \(error.localizedDescription)"
        }

        let g = preferencesStore.global
        self.sidebarCollapsed = g.sidebarCollapsed
        self.backgroundMode = g.backgroundMode
        if g.customBackgroundRGB.count == 3 {
            self.customBackgroundColor = Color(
                red: g.customBackgroundRGB[0],
                green: g.customBackgroundRGB[1],
                blue: g.customBackgroundRGB[2]
            )
        }
        self.obsBackgroundMode = g.obsBackgroundMode
        if g.obsCustomBackgroundRGB.count == 3 {
            self.obsCustomColor = Color(
                red: g.obsCustomBackgroundRGB[0],
                green: g.obsCustomBackgroundRGB[1],
                blue: g.obsCustomBackgroundRGB[2]
            )
        }
        self.selectedCameraID = g.selectedCameraID
        self.selectedMicID = g.selectedMicID
        self.alwaysOnTop = g.alwaysOnTop

        if let engine = renderEngine {
            let obsCtrl = OBSCleanWindowController(renderEngine: engine, snapshotSource: self)
            obsCtrl.onWindowClosed = { [weak self] in
                Task { @MainActor in
                    self?.obsWindowOpen = false
                }
            }
            self.obsWindowController = obsCtrl
        }

        refreshDevices()
        refreshLibrary()
    }

    public func refreshDevices() {
        availableCameras = FaceTracker.enumerateCameras()
        if selectedCameraID == nil || !availableCameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = availableCameras.first?.id
        }
        availableMics = LipSyncEngine.enumerateInputDevices()
        if selectedMicID == nil || !availableMics.contains(where: { $0.id == selectedMicID }) {
            selectedMicID = availableMics.first?.id
        }
        availableWebcamSinks = VirtualWebcamManager.discoverSinkDevices()
        if selectedWebcamSinkID == nil || !availableWebcamSinks.contains(where: { $0.id == selectedWebcamSinkID }) {
            selectedWebcamSinkID = availableWebcamSinks.first?.id
        }
        let camSt = virtualWebcam.readStatus()
        virtualWebcamStatus = camSt.status
        virtualWebcamNote = camSt.extensionNote
    }

    public func refreshLibrary() {
        libraryEntries = preferencesStore.discoverAvatars()
    }

    public func restoreLastOrDefaultAvatar() {
        if let lastPath = preferencesStore.global.lastAvatarPath,
           FileManager.default.fileExists(atPath: lastPath) {
            loadAvatar(url: URL(fileURLWithPath: lastPath))
            if loadedAvatar != nil { return }
        }
        if let first = libraryEntries.first {
            loadAvatar(url: first.url)
        }
    }

    public func loadAvatar(url: URL, addToUserLibrary: Bool = false) {
        let targetURL: URL
        if addToUserLibrary {
            let dest = preferencesStore.userLibraryDirectory.appendingPathComponent(url.lastPathComponent)
            if url.standardizedFileURL != dest.standardizedFileURL {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            targetURL = FileManager.default.fileExists(atPath: dest.path) ? dest : url
        } else {
            targetURL = url
        }

        guard let engine = renderEngine else {
            errorMessage = "Metal render engine is unavailable."
            return
        }

        do {
            let (avatar, report) = try ModelLoader.loadAndValidate(url: targetURL)
            try engine.uploadTextures(for: avatar)
            let rig = RigController(avatar: avatar)

            self.loadedAvatar = avatar
            self.loadedAvatarURL = targetURL.standardizedFileURL
            self.validationReport = report
            self.rigController = rig
            self.errorMessage = nil

            preferencesStore.recordLoadedAvatar(url: targetURL)
            refreshLibrary()

            let key = avatarPreferenceKey(avatar: avatar, url: targetURL)
            let saved = preferencesStore.preferences(forAvatarKey: key)
            applyAvatarPreferences(saved, to: rig, avatar: avatar)

            // Prime frame immediately so there's zero blank frame flash
            stepSimulationForCurrentFrame(now: CACurrentMediaTime())
        } catch {
            errorMessage = "Failed to load \"\(url.lastPathComponent)\": \(error.localizedDescription)"
        }
    }

    public func openAvatarPicker() {
        let panel = NSOpenPanel()
        panel.title = "Open SVStudio Avatar (.sat)"
        panel.allowedContentTypes = [.init(filenameExtension: "sat") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadAvatar(url: url, addToUserLibrary: false)
        }
    }

    public func importAvatarPicker() {
        let panel = NSOpenPanel()
        panel.title = "Import Avatar into SVStudio Library"
        panel.allowedContentTypes = [.init(filenameExtension: "sat") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for (idx, url) in panel.urls.enumerated() {
                if idx == panel.urls.count - 1 {
                    loadAvatar(url: url, addToUserLibrary: true)
                } else {
                    let dest = preferencesStore.userLibraryDirectory.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
            }
            refreshLibrary()
        }
    }

    public func openLibraryFolderInFinder() {
        preferencesStore.ensureLibraryDirectoryExists()
        NSWorkspace.shared.open(preferencesStore.userLibraryDirectory)
    }

    // MARK: - Controls Mutations & Persistence

    private func avatarPreferenceKey(avatar: SatLoadedAvatar, url: URL) -> String {
        "\(avatar.manifest.id)@\(url.standardizedFileURL.lastPathComponent)"
    }

    public var avatarHasBreastPhysics: Bool {
        guard let avatar = loadedAvatar else { return false }
        return avatar.manifest.features?.breastPhysics == true
            || (avatar.physics?.groups.contains(where: { $0.category == .breast }) == true)
    }

    public var avatarSupportsHandTracking: Bool {
        guard let avatar = loadedAvatar else { return false }
        if avatar.manifest.features?.handTracking == true { return true }
        return avatar.rig.parameters.contains {
            $0.id == "HandLeftFound" || $0.id == "HandLeftFinger_1_Thumb" || $0.id == "ParamArmLShoulder"
        }
    }

    public var avatarPhysicsCategories: [SatPhysicsCategory] {
        rigController?.physicsEngine.availableCategories ?? []
    }

    public var avatarDragReactions: [SatDragReactionSpec] {
        loadedAvatar?.rig.dragReactions ?? []
    }

    public var avatarHasEffects: Bool {
        guard let avatar = loadedAvatar else { return false }
        return avatar.manifest.features?.effects == true || !avatar.effects.isEmpty
    }

    public func categoryMultiplier(for cat: SatPhysicsCategory) -> Double {
        categoryPhysicsMultipliers[cat] ?? 1.0
    }

    public func setCategoryMultiplier(_ value: Double, for cat: SatPhysicsCategory) {
        categoryPhysicsMultipliers[cat] = value
        rigController?.physicsEngine.categoryMultipliers = categoryPhysicsMultipliers
        persistCurrentAvatarPreferences()
    }

    private func applyAvatarPreferences(_ prefs: PerAvatarPreferences, to rig: RigController, avatar: SatLoadedAvatar) {
        self.camera = SatCameraTransform(zoom: prefs.cameraZoom, panX: prefs.cameraPanX, panY: prefs.cameraPanY)
        self.inputMode = prefs.inputMode
        // Webcam hand tracking is disabled in the active player while preserving the underlying engine.
        self.cameraTrackingMode = .faceOnly
        self.handTrackingEnabled = false
        self.mirrorHands = prefs.mirrorHands
        self.faceSensitivity = prefs.faceSensitivity
        self.headSmoothing = prefs.headSmoothing
        self.handSensitivity = prefs.handSensitivity
        self.handSmoothing = prefs.handSmoothing
        self.autoExpressionTracking = prefs.autoExpressionTracking
        self.lipSyncGain = prefs.lipSyncGain
        self.lipSyncThreshold = prefs.lipSyncThreshold
        self.physicsEnabled = prefs.physicsEnabled
        self.physicsIntensity = prefs.physicsIntensity
        self.breastPhysicsLevel = avatarHasBreastPhysics ? prefs.breastPhysicsLevel : .off
        var catMap: [SatPhysicsCategory: Double] = [:]
        for (raw, val) in prefs.categoryPhysicsMultipliers {
            if let cat = SatPhysicsCategory(rawValue: raw) {
                catMap[cat] = val
            }
        }
        self.categoryPhysicsMultipliers = catMap
        self.dragReactionsEnabled = prefs.dragReactionsEnabled
        self.animationsEnabled = prefs.animationsEnabled
        self.effectsEnabled = avatarHasEffects ? prefs.effectsEnabled : false
        self.activeGestureId = nil

        if let expId = prefs.activeExpressionId,
           avatar.expressions.contains(where: { $0.id == expId }) {
            self.activeExpressionId = expId
            rig.expressionController.select(expressionId: expId)
        } else {
            self.activeExpressionId = nil
            rig.expressionController.select(expressionId: nil)
        }

        syncRigSettings()
        setFaceTrackingEnabled(prefs.faceTrackingEnabled, persist: false)
        setMicLipSyncEnabled(prefs.micLipSyncEnabled, persist: false)
    }

    public func persistCurrentAvatarPreferences() {
        guard let avatar = loadedAvatar, let url = loadedAvatarURL else { return }
        let key = avatarPreferenceKey(avatar: avatar, url: url)
        var encodedCats: [String: Double] = [:]
        for (cat, val) in categoryPhysicsMultipliers {
            encodedCats[cat.rawValue] = val
        }
        let prefs = PerAvatarPreferences(
            cameraZoom: camera.zoom,
            cameraPanX: camera.panX,
            cameraPanY: camera.panY,
            inputMode: inputMode,
            cameraTrackingMode: cameraTrackingMode,
            faceTrackingEnabled: faceTrackingEnabled,
            handTrackingEnabled: handTrackingEnabled,
            mirrorHands: mirrorHands,
            micLipSyncEnabled: micLipSyncEnabled,
            faceSensitivity: faceSensitivity,
            headSmoothing: headSmoothing,
            handSensitivity: handSensitivity,
            handSmoothing: handSmoothing,
            autoExpressionTracking: autoExpressionTracking,
            lipSyncGain: lipSyncGain,
            lipSyncThreshold: lipSyncThreshold,
            physicsEnabled: physicsEnabled,
            physicsIntensity: physicsIntensity,
            breastPhysicsLevel: breastPhysicsLevel,
            categoryPhysicsMultipliers: encodedCats,
            dragReactionsEnabled: dragReactionsEnabled,
            animationsEnabled: animationsEnabled,
            effectsEnabled: effectsEnabled,
            activeExpressionId: activeExpressionId
        )
        preferencesStore.savePreferences(prefs, forAvatarKey: key)
    }

    public func syncRigSettings() {
        faceTracker.trackingMode = cameraTrackingMode
        faceTracker.mirrorHands = mirrorHands
        guard let rig = rigController else { return }
        rig.inputMode = inputMode
        rig.faceSensitivity = faceSensitivity
        rig.headSmoothing = headSmoothing
        rig.autoExpressionTracking = autoExpressionTracking
        rig.handTrackingEnabled = cameraTrackingMode.tracksHands && handTrackingEnabled
        rig.handSensitivity = handSensitivity
        rig.handSmoothing = handSmoothing
        rig.dragReactionsEnabled = dragReactionsEnabled
        rig.animationsEnabled = animationsEnabled
        rig.effectsEnabled = effectsEnabled
        rig.physicsEngine.enabled = physicsEnabled
        rig.physicsEngine.globalIntensity = physicsIntensity
        rig.physicsEngine.breastPhysicsLevel = breastPhysicsLevel
        rig.physicsEngine.categoryMultipliers = categoryPhysicsMultipliers
        lipSync.configure(noiseFloor: lipSyncThreshold, gain: lipSyncGain)
    }

    public func setCameraTrackingMode(_ mode: CameraTrackingMode) {
        cameraTrackingMode = mode
        handTrackingEnabled = mode.tracksHands
        syncRigSettings()
        persistCurrentAvatarPreferences()
    }

    public func setMirrorHands(_ mirrored: Bool) {
        mirrorHands = mirrored
        syncRigSettings()
        persistCurrentAvatarPreferences()
    }

    public func setDragReactionsEnabled(_ enabled: Bool) {
        dragReactionsEnabled = enabled
        syncRigSettings()
        persistCurrentAvatarPreferences()
    }

    public var gestureAnimations: [SatAnimationRef] {
        (loadedAvatar?.manifest.animations ?? []).filter { $0.autoPlay == false }
    }

    public func setAutoExpressionTracking(_ enabled: Bool) {
        autoExpressionTracking = enabled
        rigController?.autoExpressionTracking = enabled
        persistCurrentAvatarPreferences()
    }

    public func selectExpression(_ id: String?, manualOverride: Bool = true) {
        if manualOverride && autoExpressionTracking {
            autoExpressionTracking = false
            rigController?.autoExpressionTracking = false
        }
        activeExpressionId = id
        rigController?.expressionController.select(expressionId: id)
        persistCurrentAvatarPreferences()
    }

    public func selectGesture(_ id: String?) {
        activeGestureId = id
        rigController?.selectGesture(id)
    }

    public func notifyViewportDrag(deltaX: Double, deltaY: Double, isDragging: Bool) {
        rigController?.notifyDrag(deltaX: deltaX, deltaY: deltaY, isDragging: isDragging)
    }

    public func updateCamera(_ next: SatCameraTransform) {
        camera = next
        persistCurrentAvatarPreferences()
    }

    public func resetCamera() {
        camera = SatCameraTransform(zoom: 1.0, panX: 0.0, panY: 0.0)
        persistCurrentAvatarPreferences()
    }

    public func fitUpperBodyPreset() {
        let isPortraitFullBody = (loadedAvatar?.manifest.canvas.height ?? 1) > (loadedAvatar?.manifest.canvas.width ?? 1) * 1.2
        camera = SatCameraTransform(zoom: isPortraitFullBody ? 1.85 : 1.35, panX: 0.0, panY: isPortraitFullBody ? 460.0 : 0.0)
        persistCurrentAvatarPreferences()
    }

    public func setBackgroundMode(_ mode: SatBackgroundMode) {
        backgroundMode = mode
        preferencesStore.updateGlobal { $0.backgroundMode = mode }
    }

    public func setCustomBackgroundColor(_ color: Color) {
        customBackgroundColor = color
        let comps = rgbComponents(of: color)
        preferencesStore.updateGlobal { $0.customBackgroundRGB = comps }
    }

    public func setOBSBackgroundMode(_ mode: SatBackgroundMode) {
        obsBackgroundMode = mode
        preferencesStore.updateGlobal { $0.obsBackgroundMode = mode }
    }

    public func setOBSCustomColor(_ color: Color) {
        obsCustomColor = color
        let comps = rgbComponents(of: color)
        preferencesStore.updateGlobal { $0.obsCustomBackgroundRGB = comps }
    }

    public func toggleSidebar() {
        sidebarCollapsed.toggle()
        preferencesStore.updateGlobal { $0.sidebarCollapsed = sidebarCollapsed }
    }

    public func toggleAlwaysOnTop() {
        alwaysOnTop.toggle()
        preferencesStore.updateGlobal { $0.alwaysOnTop = alwaysOnTop }
        for win in NSApp.windows where win.title != "SVStudio OBS Output" && win.title != "Satella OBS Output" {
            win.level = alwaysOnTop ? .floating : .normal
        }
    }

    public func toggleOBSWindow() {
        guard let obsWindowController else { return }
        if obsWindowController.isOpen {
            obsWindowController.closeWindow()
            obsWindowOpen = false
        } else {
            obsWindowController.openWindow()
            obsWindowOpen = true
        }
    }

    public func setVirtualWebcamEnabled(_ enabled: Bool) {
        virtualWebcamEnabled = enabled
        guard enabled, let engine = renderEngine else {
            virtualWebcam.stop()
            let st = virtualWebcam.readStatus()
            virtualWebcamStatus = st.status
            virtualWebcamNote = st.extensionNote
            return
        }
        refreshDevices()
        let box = webcamSnapshotBox
        virtualWebcam.start(sinkID: selectedWebcamSinkID, fps: virtualWebcamFPS, renderEngine: engine) {
            box.get()
        }
        let st = virtualWebcam.readStatus()
        virtualWebcamStatus = st.status
        virtualWebcamNote = st.extensionNote
        if case .waitingForExtension = st.status {
            virtualWebcamEnabled = false
            sidebarCollapsed = false
            selectedInspectorTab = 3
        }
    }

    public func activateCameraExtension() {
        virtualWebcam.installEmbeddedExtensionIfPresent()
        let st = virtualWebcam.readStatus()
        virtualWebcamStatus = st.status
        virtualWebcamNote = st.extensionNote
    }

    public func openCameraExtensionsSettings() {
        VirtualWebcamManager.openCameraExtensionsSettings()
    }

    public func setFaceTrackingEnabled(_ enabled: Bool, persist: Bool = true) {
        faceTrackingEnabled = enabled
        if enabled {
            faceTracker.start(cameraID: selectedCameraID)
        } else {
            faceTracker.stop()
        }
        faceTrackerStatus = faceTracker.readState().status
        if persist { persistCurrentAvatarPreferences() }
    }

    public func selectCamera(_ id: String) {
        selectedCameraID = id
        preferencesStore.updateGlobal { $0.selectedCameraID = id }
        if faceTrackingEnabled {
            faceTracker.start(cameraID: id)
        }
    }

    public func calibrateNeutralHead() {
        faceTracker.calibrateNeutral()
    }

    public func setMicLipSyncEnabled(_ enabled: Bool, persist: Bool = true) {
        micLipSyncEnabled = enabled
        lipSync.configure(noiseFloor: lipSyncThreshold, gain: lipSyncGain)
        if enabled {
            lipSync.start(deviceUID: selectedMicID)
        } else {
            lipSync.stop()
        }
        lipSyncStatus = lipSync.readState().status
        if persist { persistCurrentAvatarPreferences() }
    }

    public func selectMicrophone(_ id: String) {
        selectedMicID = id
        preferencesStore.updateGlobal { $0.selectedMicID = id }
        if micLipSyncEnabled {
            lipSync.start(deviceUID: id)
        }
    }

    public func calibrateMicNoiseFloor() {
        lipSyncThreshold = lipSync.calibrateNoiseFloor()
        persistCurrentAvatarPreferences()
    }

    public func resetPhysicsAndParameters() {
        rigController?.resetParametersToDefault()
        rigController?.physicsEngine.reset()
        activeExpressionId = nil
        persistCurrentAvatarPreferences()
    }

    public func setManualOverride(parameter: String, value: Double?) {
        guard let rig = rigController else { return }
        if let value {
            rig.manualOverrides[parameter] = value
        } else {
            rig.manualOverrides.removeValue(forKey: parameter)
        }
    }

    public func clearManualOverrides() {
        rigController?.manualOverrides.removeAll()
    }

    // MARK: - FrameSnapshotProvider

    public func stepSimulationForCurrentFrame(now: CFTimeInterval) {
        let dt = min(0.05, max(1.0 / 240.0, now - lastSimTime))
        lastSimTime = now

        guard let rig = rigController else { return }
        let (faceSample, faceStatus) = faceTrackingEnabled
            ? faceTracker.readState()
            : (TrackingSample(), FaceTrackerStatus.inactive)
        let (micMouth, micLevel, micStatus) = micLipSyncEnabled
            ? lipSync.readState()
            : (0.0, 0.0, LipSyncStatus.inactive)

        let stepped = rig.step(
            dt: dt,
            tracking: faceSample,
            micMouthOpen: micMouth,
            isMicActive: micLipSyncEnabled && micStatus == .running
        )
        self.currentDrawables = stepped.drawables
        self.currentEffects = stepped.effects

        if let avatar = loadedAvatar {
            let comps = rgbComponents(of: customBackgroundColor)
            let snap = LiveRenderSnapshot(
                canvasSize: avatar.manifest.canvas,
                camera: camera,
                drawables: stepped.drawables,
                effects: stepped.effects,
                background: virtualWebcamBackground,
                customColor: SIMD3<Float>(Float(comps[0]), Float(comps[1]), Float(comps[2]))
            )
            webcamSnapshotBox.set(snap)
        }

        if now - lastTelemetrySyncTime >= 0.08 {
            lastTelemetrySyncTime = now
            self.faceTrackerStatus = faceStatus
            self.liveTrackingSample = faceSample
            self.lipSyncStatus = micStatus
            self.liveMicLevel = micLevel
            if self.autoExpressionTracking {
                self.activeExpressionId = rig.expressionController.activeExpressionId
            }
            self.activeGestureId = rig.activeGestureId
            let camSt = virtualWebcam.readStatus()
            self.virtualWebcamStatus = camSt.status
            self.virtualWebcamNote = camSt.extensionNote
        }
    }

    public func currentMainFrameSnapshot() -> LiveRenderSnapshot? {
        guard let avatar = loadedAvatar else { return nil }
        let comps = rgbComponents(of: customBackgroundColor)
        return LiveRenderSnapshot(
            canvasSize: avatar.manifest.canvas,
            camera: camera,
            drawables: currentDrawables,
            effects: currentEffects,
            background: backgroundMode,
            customColor: SIMD3<Float>(Float(comps[0]), Float(comps[1]), Float(comps[2]))
        )
    }

    public func currentOBSFrameSnapshot() -> LiveRenderSnapshot? {
        guard let avatar = loadedAvatar else { return nil }
        let comps = rgbComponents(of: obsCustomColor)
        return LiveRenderSnapshot(
            canvasSize: avatar.manifest.canvas,
            camera: camera,
            drawables: currentDrawables,
            effects: currentEffects,
            background: obsBackgroundMode,
            customColor: SIMD3<Float>(Float(comps[0]), Float(comps[1]), Float(comps[2]))
        )
    }

    public func reportMainViewportMetrics(fps: Double, frameMs: Double) {
        self.fpsDisplay = fps
        self.frameMsDisplay = frameMs
    }

    private func rgbComponents(of color: Color) -> [Double] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        return [Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent)]
    }
}
