import Foundation
import SwiftUI
import AppKit
import SatellaCore
import SatellaRender

public typealias SVStudioMainView = SatellaMainView

public struct SatellaMainView: View {
    @Bindable var controller: AppController

    public init(controller: AppController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 0) {
            viewportPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !controller.sidebarCollapsed {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                inspectorSidebar
                    .frame(width: 342)
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor(srgbRed: 0.095, green: 0.098, blue: 0.125, alpha: 1.0)))
            }
        }
        .preferredColorScheme(.dark)
        .background(Color.black)
        .sheet(isPresented: $controller.showValidationDetails) {
            validationSheet
        }
        .alert(
            "Notice",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK") { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    // MARK: - Viewport

    private var viewportPane: some View {
        ZStack {
            if controller.backgroundMode == .transparent {
                CheckerboardBackdropView()
                    .allowsHitTesting(false)
            }

            if let engine = controller.renderEngine {
                SatellaMetalViewport(
                    renderEngine: engine,
                    snapshotProvider: controller,
                    camera: controller.camera,
                    isTransparentWindow: false,
                    onCameraChanged: { cam in
                        controller.updateCamera(cam)
                    },
                    onResetCamera: {
                        controller.resetCamera()
                    },
                    onDropSatFile: { url in
                        controller.loadAvatar(url: url, addToUserLibrary: false)
                    },
                    onDragMotion: { dx, dy, dragging in
                        controller.notifyViewportDrag(deltaX: dx, deltaY: dy, isDragging: dragging)
                    }
                )
            } else {
                emptyStateOverlay
            }

            if controller.loadedAvatar == nil {
                emptyStateOverlay
            }

            // Minimal Studio HUD Overlay
            VStack {
                HStack(alignment: .top, spacing: 10) {
                    avatarStatusPill
                    Spacer()
                    telemetryStatusPill
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer()

                HStack(alignment: .bottom, spacing: 10) {
                    quickViewportBar
                    Spacer()
                    Button {
                        controller.toggleSidebar()
                    } label: {
                        Label(
                            controller.sidebarCollapsed ? "Show Studio" : "Hide Studio",
                            systemImage: controller.sidebarCollapsed ? "sidebar.right" : "sidebar.trailing"
                        )
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private var avatarStatusPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple.opacity(0.95))

            VStack(alignment: .leading, spacing: 1) {
                Text("SVStudio")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(controller.loadedAvatar?.manifest.name ?? "No Avatar Loaded")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }

            if let report = controller.validationReport {
                Button {
                    controller.showValidationDetails = true
                } label: {
                    Image(systemName: report.valid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.valid ? .green : .yellow)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(report.valid ? "Inspect avatar validation details" : "View warnings / errors")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var telemetryStatusPill: some View {
        HStack(spacing: 10) {
            if controller.faceTrackingEnabled {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor(for: controller.faceTrackerStatus))
                        .frame(width: 7, height: 7)
                    Text(controller.liveTrackingSample.isFaceDetected ? "Face Active" : "Searching")
                        .font(.caption2.weight(.medium))
                }
            }

            if controller.micLipSyncEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                        .foregroundStyle(controller.lipSyncStatus == .running ? .green : .yellow)
                    ProgressView(value: min(1.0, controller.liveMicLevel * 8.0))
                        .frame(width: 28)
                        .tint(.green)
                }
            }

            if controller.virtualWebcamEnabled {
                Label("CAM", systemImage: "video.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            }

            if controller.obsWindowOpen {
                Label("OBS", systemImage: "macwindow")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.mint)
            }

            Text(String(format: "%.0f fps", controller.fpsDisplay))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var quickViewportBar: some View {
        HStack(spacing: 6) {
            Button {
                controller.resetCamera()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())

            Button {
                controller.fitUpperBodyPreset()
            } label: {
                Label("Upper", systemImage: "person.crop.square")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())

            Divider().frame(height: 14)

            Menu {
                ForEach(SatBackgroundMode.allCases, id: \.self) { mode in
                    Button {
                        controller.setBackgroundMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if controller.backgroundMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(controller.backgroundMode.displayName, systemImage: "swatchpalette")
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var emptyStateOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 46))
                .foregroundStyle(.purple.opacity(0.85))
            Text("Drop a .sat Avatar Anywhere")
                .font(.title3.weight(.semibold))
            Text("Supports VTube Studio face parameters, Live2D-style deformers, and expressive emotions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Open Avatar (.sat)...") { controller.openAvatarPicker() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                Button("Import to Library") { controller.importAvatarPicker() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Studio Sidebar

    private var inspectorSidebar: some View {
        VStack(spacing: 0) {
            // Top Icon + Label Segmented Tab Header
            HStack(spacing: 4) {
                sidebarTabButton(index: 0, title: "Avatars", icon: "person.2")
                sidebarTabButton(index: 1, title: "Tracking", icon: "face.smiling")
                sidebarTabButton(index: 2, title: "Rig & FX", icon: "slider.horizontal.3")
                sidebarTabButton(index: 3, title: "Output", icon: "video")
            }
            .padding(8)
            .background(Color.black.opacity(0.35))

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch controller.selectedInspectorTab {
                    case 0: avatarTabContent
                    case 1: trackingTabContent
                    case 2: rigAndFXTabContent
                    default: outputTabContent
                    }
                }
                .padding(12)
            }
        }
    }

    private func sidebarTabButton(index: Int, title: String, icon: String) -> some View {
        let selected = controller.selectedInspectorTab == index
        return Button {
            controller.selectedInspectorTab = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.purple.opacity(0.35) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.purple.opacity(0.65) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func studioCard<Content: View>(
        title: String,
        icon: String,
        accent: Color = .purple,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
            }
            content()
        }
        .padding(12)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Tab 0: Avatars

    private var avatarTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            studioCard(title: "Avatar Library", icon: "square.grid.2x2") {
                HStack(spacing: 6) {
                    Button {
                        controller.openAvatarPicker()
                    } label: {
                        Label("Open .sat", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)

                    Button {
                        controller.importAvatarPicker()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        controller.openLibraryFolderInFinder()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open SVStudio Avatars Folder")

                    Button {
                        controller.refreshLibrary()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Rescan Avatars")
                }

                if controller.libraryEntries.isEmpty {
                    Text("No `.sat` packages found. Click Open or drag a `.sat` file onto the canvas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(controller.libraryEntries) { entry in
                            let isCurrent = controller.loadedAvatarURL?.standardizedFileURL == entry.url.standardizedFileURL
                            Button {
                                controller.loadAvatar(url: entry.url, addToUserLibrary: false)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isCurrent ? Color.purple.opacity(0.32) : Color.white.opacity(0.06))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: isCurrent ? "sparkles" : "person.crop.circle")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isCurrent ? .purple : .secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text(entry.sourceLabel)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isCurrent {
                                        Text("Active")
                                            .font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.20), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isCurrent ? Color.purple.opacity(0.14) : Color.black.opacity(0.22))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(isCurrent ? Color.purple.opacity(0.60) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let avatar = controller.loadedAvatar {
                studioCard(title: "Active Model Capabilities", icon: "info.circle", accent: .mint) {
                    Text(avatar.manifest.name)
                        .font(.subheadline.weight(.semibold))
                    if let desc = avatar.manifest.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Dynamic capability chips driven strictly by the loaded avatar's schema
                    FlowBadgesView(badges: activeCapabilityBadges(for: avatar))

                    Divider().overlay(Color.white.opacity(0.08))

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        GridRow {
                            Text("Canvas").foregroundStyle(.secondary)
                            Text("\(Int(avatar.manifest.canvas.width)) × \(Int(avatar.manifest.canvas.height))")
                        }
                        GridRow {
                            Text("Parameters").foregroundStyle(.secondary)
                            Text("\(avatar.rig.parameters.count) rigged")
                        }
                        GridRow {
                            Text("Physics Groups").foregroundStyle(.secondary)
                            Text("\(avatar.physics?.groups.count ?? 0) chains")
                        }
                        GridRow {
                            Text("Drag Reactions").foregroundStyle(.secondary)
                            Text(controller.avatarDragReactions.isEmpty ? "None" : "\(controller.avatarDragReactions.count) defined")
                        }
                    }
                    .font(.caption2)

                    if let report = controller.validationReport {
                        HStack {
                            Label(
                                report.valid ? "Validated" : "Needs Attention",
                                systemImage: report.valid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(report.valid ? .green : .yellow)
                            Spacer()
                            Button("Inspect...") { controller.showValidationDetails = true }
                                .font(.caption2)
                                .buttonStyle(.link)
                        }
                    }
                }
            }
        }
    }

    private func activeCapabilityBadges(for avatar: SatLoadedAvatar) -> [(String, Color)] {
        var list: [(String, Color)] = []
        if avatar.manifest.features?.faceTracking != false { list.append(("VTS Face", .purple)) }
        if controller.avatarHasBreastPhysics { list.append(("Bust Physics", .pink)) }
        if !controller.avatarDragReactions.isEmpty { list.append(("Drag Reactions", .orange)) }
        if controller.avatarHasEffects { list.append(("Particles/FX", .mint)) }
        if avatar.manifest.features?.concealedEyes == true { list.append(("Concealed Eyes", .indigo)) }
        return list
    }

    // MARK: - Tab 1: Tracking

    private var trackingTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            studioCard(title: "Webcam Face & Expression Tracking", icon: "camera.viewfinder", accent: .cyan) {
                Toggle(isOn: Binding(
                    get: { controller.faceTrackingEnabled },
                    set: { controller.setFaceTrackingEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable Face Tracking")
                            .font(.caption.weight(.semibold))
                        Text(controller.faceTrackerStatus.descriptionText)
                            .font(.caption2)
                            .foregroundStyle(statusColor(for: controller.faceTrackerStatus))
                    }
                }
                .toggleStyle(.switch)

                if !controller.availableCameras.isEmpty {
                    Picker("Camera", selection: Binding(
                        get: { controller.selectedCameraID ?? controller.availableCameras.first?.id ?? "" },
                        set: { controller.selectCamera($0) }
                    )) {
                        ForEach(controller.availableCameras) { cam in
                            Text(cam.name).tag(cam.id)
                        }
                    }
                    .font(.caption2)
                }

                DisclosureGroup("Calibration & Tuning", isExpanded: $controller.calibrationExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            controller.calibrateNeutralHead()
                        } label: {
                            Label("Calibrate Neutral Pose & Expressions", systemImage: "viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan.opacity(0.85))
                        .controlSize(.small)

                        Toggle("Auto-Detect Facial Emotions", isOn: Binding(
                            get: { controller.autoExpressionTracking },
                            set: { controller.setAutoExpressionTracking($0) }
                        ))
                        .font(.caption2)

                        labeledSlider(
                            "Face Sensitivity",
                            value: Binding(
                                get: { controller.faceSensitivity },
                                set: {
                                    controller.faceSensitivity = $0
                                    controller.syncRigSettings()
                                    controller.persistCurrentAvatarPreferences()
                                }
                            ),
                            range: 0.4...2.2,
                            format: "%.2fx"
                        )

                        labeledSlider(
                            "Head Smoothing",
                            value: Binding(
                                get: { controller.headSmoothing },
                                set: {
                                    controller.headSmoothing = $0
                                    controller.syncRigSettings()
                                    controller.persistCurrentAvatarPreferences()
                                }
                            ),
                            range: 0.05...0.90,
                            format: "%.2f"
                        )
                    }
                    .padding(.top, 6)
                }
                .font(.caption.weight(.medium))
            }

            if controller.faceTrackingEnabled {
                studioCard(title: "Live Face Telemetry", icon: "waveform.path.ecg", accent: .green) {
                    let s = controller.liveTrackingSample
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Head").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "X %.0f° · Y %.0f° · Z %.0f°", s.angleX, s.angleY, s.angleZ))
                                .font(.caption2.monospacedDigit())
                        }
                        HStack(spacing: 10) {
                            miniBarMetric(label: "Mouth", value: s.mouthOpenY, tint: .orange)
                            miniBarMetric(label: "Smile", value: max(0, (s.mouthForm + 1.0) * 0.5), tint: .pink)
                            miniBarMetric(label: "Brow", value: max(0, (s.browLeftY + s.browRightY) * 0.25 + 0.5), tint: .purple)
                        }
                        if let det = s.detectedExpression {
                            HStack {
                                Text("Detected Expression")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(det.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.25), in: Capsule())
                            }
                        }
                    }
                }
            }

            studioCard(title: "Speech & Lip-Sync", icon: "mic.circle", accent: .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mouth Source Priority")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { controller.inputMode },
                        set: {
                            controller.inputMode = $0
                            controller.syncRigSettings()
                            controller.persistCurrentAvatarPreferences()
                        }
                    )) {
                        ForEach(TrackingInputMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Toggle(isOn: Binding(
                    get: { controller.micLipSyncEnabled },
                    set: { controller.setMicLipSyncEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Microphone Lip-Sync")
                            .font(.caption.weight(.semibold))
                        Text(controller.lipSyncStatus.descriptionText)
                            .font(.caption2)
                            .foregroundStyle(controller.lipSyncStatus == .running ? .green : .secondary)
                    }
                }
                .toggleStyle(.switch)

                if !controller.availableMics.isEmpty {
                    Picker("Input", selection: Binding(
                        get: { controller.selectedMicID ?? controller.availableMics.first?.id ?? "" },
                        set: { controller.selectMicrophone($0) }
                    )) {
                        ForEach(controller.availableMics) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .font(.caption2)
                }

                HStack(spacing: 8) {
                    Text("Level")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: min(1.0, controller.liveMicLevel * 8.0))
                        .tint(.green)
                }

                labeledSlider(
                    "Voice Gain",
                    value: Binding(
                        get: { controller.lipSyncGain },
                        set: {
                            controller.lipSyncGain = $0
                            controller.syncRigSettings()
                            controller.persistCurrentAvatarPreferences()
                        }
                    ),
                    range: 0.4...4.0,
                    format: "%.2fx"
                )

                labeledSlider(
                    "Noise Gate",
                    value: Binding(
                        get: { controller.lipSyncThreshold },
                        set: {
                            controller.lipSyncThreshold = $0
                            controller.syncRigSettings()
                            controller.persistCurrentAvatarPreferences()
                        }
                    ),
                    range: 0.005...0.15,
                    format: "%.3f"
                )

                Button {
                    controller.calibrateMicNoiseFloor()
                } label: {
                    Label("Calibrate Ambient Noise", systemImage: "waveform.and.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func miniBarMetric(label: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: max(3, geo.size.width * CGFloat(max(0, min(1, value)))))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Tab 2: Rig, Gestures, Adaptive Physics & VTS Parameters

    private var rigAndFXTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let avatar = controller.loadedAvatar {
                // 1. Facial Expressions
                if !avatar.expressions.isEmpty {
                    studioCard(title: "Facial Expressions", icon: "theatermasks") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(avatar.expressions, id: \.id) { exp in
                                let active = controller.activeExpressionId == exp.id
                                Button {
                                    controller.selectExpression(active ? nil : exp.id)
                                } label: {
                                    Text(exp.name)
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(active ? .purple : Color.white.opacity(0.10))
                            }
                        }

                        Button("Reset to Neutral / Auto") {
                            controller.selectExpression(avatar.manifest.defaultExpression, manualOverride: false)
                            controller.setAutoExpressionTracking(true)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // 2. Per-Avatar Adaptive Physics Settings
                studioCard(title: "Avatar Physics", icon: "wind", accent: .mint) {
                    Toggle("Enable Secondary Physics", isOn: Binding(
                        get: { controller.physicsEnabled },
                        set: {
                            controller.physicsEnabled = $0
                            controller.syncRigSettings()
                            controller.persistCurrentAvatarPreferences()
                        }
                    ))
                    .font(.caption.weight(.medium))

                    labeledSlider(
                        "Overall Physics",
                        value: Binding(
                            get: { controller.physicsIntensity },
                            set: {
                                controller.physicsIntensity = $0
                                controller.syncRigSettings()
                                controller.persistCurrentAvatarPreferences()
                            }
                        ),
                        range: 0.0...2.0,
                        format: "%.2fx"
                    )

                    if controller.avatarHasBreastPhysics {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Breast Physics (This Avatar)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { controller.breastPhysicsLevel },
                                set: {
                                    controller.breastPhysicsLevel = $0
                                    controller.syncRigSettings()
                                    controller.persistCurrentAvatarPreferences()
                                }
                            )) {
                                ForEach(BreastPhysicsLevel.allCases, id: \.self) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    let otherCats = controller.avatarPhysicsCategories.filter { $0 != .breast }
                    if !otherCats.isEmpty {
                        Divider().overlay(Color.white.opacity(0.08))
                        ForEach(otherCats, id: \.self) { cat in
                            labeledSlider(
                                "\(cat.displayName) Physics",
                                value: Binding(
                                    get: { controller.categoryMultiplier(for: cat) },
                                    set: { controller.setCategoryMultiplier($0, for: cat) }
                                ),
                                range: 0.0...2.0,
                                format: "%.2fx"
                            )
                        }
                    }
                }

                // 4. Avatar-Specific Interactions & Effects
                studioCard(title: "Behavior & Visual FX", icon: "wand.and.stars", accent: .orange) {
                    if !controller.avatarDragReactions.isEmpty {
                        let names = controller.avatarDragReactions.map(\.name).joined(separator: ", ")
                        Toggle(isOn: Binding(
                            get: { controller.dragReactionsEnabled },
                            set: { controller.setDragReactionsEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Drag Reactions")
                                    .font(.caption.weight(.medium))
                                Text(names)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Toggle("Idle Breathing & Sway", isOn: Binding(
                        get: { controller.animationsEnabled },
                        set: {
                            controller.animationsEnabled = $0
                            controller.syncRigSettings()
                            controller.persistCurrentAvatarPreferences()
                        }
                    ))
                    .font(.caption.weight(.medium))

                    if controller.avatarHasEffects {
                        Toggle("Particles / Visual FX", isOn: Binding(
                            get: { controller.effectsEnabled },
                            set: {
                                controller.effectsEnabled = $0
                                controller.syncRigSettings()
                                controller.persistCurrentAvatarPreferences()
                            }
                        ))
                        .font(.caption.weight(.medium))
                    }

                    Button {
                        controller.resetPhysicsAndParameters()
                    } label: {
                        Label("Reset Pose & Physics Springs", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // 5. VTube Studio Parameter Standard & Test Drawer
                DisclosureGroup("VTS Parameters & Inspector", isExpanded: $controller.showParameterTestDrawer) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Group", selection: $controller.paramFilterCategory) {
                            Text("All").tag(0)
                            Text("Face").tag(1)
                            Text("Mouth").tag(2)
                            Text("Body").tag(3)
                            Text("FX").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)

                        HStack {
                            Text("\(filteredParameters(for: avatar).count) parameters")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear Overrides") {
                                controller.clearManualOverrides()
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        ForEach(filteredParameters(for: avatar), id: \.id) { param in
                            let currentVal = controller.rigController?.manualOverrides[param.id]
                                ?? controller.rigController?.paramValues[param.id]
                                ?? param.default
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(param.name ?? param.id)
                                        .font(.caption2.weight(.medium))
                                    Text(param.id)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f", currentVal))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.purple)
                                }
                                Slider(
                                    value: Binding(
                                        get: { currentVal },
                                        set: { controller.setManualOverride(parameter: param.id, value: $0) }
                                    ),
                                    in: param.min...max(param.min + 0.001, param.max)
                                )
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.semibold))
                .padding(12)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private func filteredParameters(for avatar: SatLoadedAvatar) -> [SatParameterSpec] {
        let visible = avatar.rig.parameters.filter {
            $0.group != "Left Hand" && $0.group != "Right Hand" && $0.group != "Arms"
        }
        switch controller.paramFilterCategory {
        case 1:
            return visible.filter { $0.group == "Face" || $0.group == "Brows & Eyes" || $0.group == "Eyes" || $0.group == "Head" }
        case 2:
            return visible.filter { $0.group == "Mouth" }
        case 3:
            return visible.filter { $0.group == "Body" }
        case 4:
            return visible.filter { $0.group == "Clothing" || $0.group == "Effects" || $0.group == "Physics" }
        default:
            return visible
        }
    }

    // MARK: - Tab 3: Output, OBS & Virtual Webcam

    private var outputTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            studioCard(title: "Studio Backdrop", icon: "photo.fill") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(SatBackgroundMode.allCases, id: \.self) { mode in
                        Button {
                            controller.setBackgroundMode(mode)
                        } label: {
                            Text(mode.displayName)
                                .font(.caption2.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(controller.backgroundMode == mode ? .purple : Color.white.opacity(0.10))
                    }
                }

                if controller.backgroundMode == .custom {
                    ColorPicker(
                        "Backdrop Color",
                        selection: Binding(
                            get: { controller.customBackgroundColor },
                            set: { controller.setCustomBackgroundColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .font(.caption2)
                }
            }

            studioCard(title: "OBS Clean Feed Window", icon: "macwindow.on.rectangle", accent: .mint) {
                Text("Borderless clean canvas output for OBS Window Capture (Chroma Green or Alpha Transparency).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    controller.toggleOBSWindow()
                } label: {
                    Label(
                        controller.obsWindowOpen ? "Close OBS Clean Window" : "Open OBS Clean Window",
                        systemImage: controller.obsWindowOpen ? "xmark.circle.fill" : "arrow.up.right.square.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.obsWindowOpen ? .red.opacity(0.85) : .mint.opacity(0.85))
                .controlSize(.small)

                Picker("OBS Backdrop", selection: Binding(
                    get: { controller.obsBackgroundMode },
                    set: { controller.setOBSBackgroundMode($0) }
                )) {
                    ForEach(SatBackgroundMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .font(.caption2)

                if controller.obsBackgroundMode == .custom {
                    ColorPicker(
                        "OBS Color",
                        selection: Binding(
                            get: { controller.obsCustomColor },
                            set: { controller.setOBSCustomColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .font(.caption2)
                }
            }

            studioCard(title: "macOS Virtual Webcam", icon: "web.camera", accent: .red) {
                Toggle(isOn: Binding(
                    get: { controller.virtualWebcamEnabled },
                    set: { controller.setVirtualWebcamEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Broadcast Virtual Webcam")
                            .font(.caption.weight(.semibold))
                        Text(controller.virtualWebcamStatus.descriptionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if !controller.availableWebcamSinks.isEmpty {
                    Picker("Sink Device", selection: Binding(
                        get: { controller.selectedWebcamSinkID ?? controller.availableWebcamSinks.first?.id ?? "" },
                        set: {
                            controller.selectedWebcamSinkID = $0
                            if controller.virtualWebcamEnabled {
                                controller.setVirtualWebcamEnabled(true)
                            }
                        }
                    )) {
                        ForEach(controller.availableWebcamSinks) { sink in
                            Text("\(sink.deviceName) (\(sink.width)×\(sink.height))").tag(sink.id)
                        }
                    }
                    .font(.caption2)
                }

                Picker("Virtual Feed BG", selection: Binding(
                    get: { controller.virtualWebcamBackground },
                    set: { controller.virtualWebcamBackground = $0 }
                )) {
                    ForEach([SatBackgroundMode.black, .greenScreen, .white, .custom], id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .font(.caption2)

                Picker("Frame Rate", selection: $controller.virtualWebcamFPS) {
                    Text("30 fps").tag(30.0)
                    Text("60 fps").tag(60.0)
                }
                .pickerStyle(.segmented)
                .font(.caption2)

                HStack(spacing: 8) {
                    Button("Activate Extension") {
                        controller.activateCameraExtension()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Camera Extensions...") {
                        controller.openCameraExtensionsSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let note = controller.virtualWebcamNote, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            studioCard(title: "Window Options", icon: "macwindow") {
                Toggle("Always Keep SVStudio On Top", isOn: Binding(
                    get: { controller.alwaysOnTop },
                    set: { _ in controller.toggleAlwaysOnTop() }
                ))
                .font(.caption.weight(.medium))
            }
        }
    }

    // MARK: - Validation Sheet & Helpers

    private var validationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Avatar Validation Report")
                    .font(.headline)
                Spacer()
                Button("Close") { controller.showValidationDetails = false }
            }
            if let rep = controller.validationReport {
                HStack(spacing: 8) {
                    Image(systemName: rep.valid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(rep.valid ? .green : .red)
                    Text(rep.valid ? "Passed All Structural & Schema Checks" : "Validation Failed")
                        .font(.subheadline.weight(.semibold))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(rep.errors.enumerated()), id: \.offset) { _, err in
                            Label(err, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        ForEach(Array(rep.warnings.enumerated()), id: \.offset) { _, warn in
                            Label(warn, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                        if rep.errors.isEmpty && rep.warnings.isEmpty {
                            Text("No errors or warnings reported.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }

    private func statusColor(for st: FaceTrackerStatus) -> Color {
        switch st {
        case .inactive: return .gray
        case .requestingPermission: return .orange
        case .running(let face, let hands): return (face || hands > 0) ? .green : .yellow
        case .noCamera, .permissionDenied, .error: return .red
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption2.monospacedDigit())
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }
}

private struct FlowBadgesView: View {
    let badges: [(String, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(badges, id: \.0) { item in
                Text(item.0)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(item.1.opacity(0.20), in: Capsule())
                    .foregroundStyle(item.1)
            }
        }
    }
}

extension SatPhysicsCategory {
    var displayName: String {
        switch self {
        case .hair: return "Hair"
        case .clothing: return "Cloak / Clothing"
        case .breast: return "Breast"
        case .accessory: return "Accessory"
        case .custom: return "Custom"
        }
    }
}

private struct CheckerboardBackdropView: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 18
            let cols = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            let dark = Color(white: 0.14)
            let light = Color(white: 0.22)
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: CGFloat(c) * tile, y: CGFloat(r) * tile, width: tile, height: tile)
                    ctx.fill(Path(rect), with: .color(((r + c) % 2 == 0) ? dark : light))
                }
            }
        }
    }
}

extension SatBackgroundMode {
    var displayName: String {
        switch self {
        case .black: return "Studio Dark"
        case .greenScreen: return "Chroma Green"
        case .white: return "White"
        case .checkerboard: return "Checkerboard"
        case .transparent: return "Transparent"
        case .custom: return "Custom"
        }
    }
}
