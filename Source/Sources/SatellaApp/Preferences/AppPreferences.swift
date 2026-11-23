import Foundation
import SatellaCore
import SatellaRender

public struct GlobalPreferences: Codable, Sendable, Equatable {
    public var lastAvatarPath: String?
    public var recentAvatarPaths: [String]
    public var sidebarCollapsed: Bool
    public var backgroundMode: SatBackgroundMode
    public var customBackgroundRGB: [Double]
    public var obsBackgroundMode: SatBackgroundMode
    public var obsCustomBackgroundRGB: [Double]
    public var selectedCameraID: String?
    public var selectedMicID: String?
    public var alwaysOnTop: Bool

    public init(
        lastAvatarPath: String? = nil,
        recentAvatarPaths: [String] = [],
        sidebarCollapsed: Bool = false,
        backgroundMode: SatBackgroundMode = .black,
        customBackgroundRGB: [Double] = [0.06, 0.05, 0.10],
        obsBackgroundMode: SatBackgroundMode = .greenScreen,
        obsCustomBackgroundRGB: [Double] = [0.0, 1.0, 0.0],
        selectedCameraID: String? = nil,
        selectedMicID: String? = nil,
        alwaysOnTop: Bool = false
    ) {
        self.lastAvatarPath = lastAvatarPath
        self.recentAvatarPaths = recentAvatarPaths
        self.sidebarCollapsed = sidebarCollapsed
        self.backgroundMode = backgroundMode
        self.customBackgroundRGB = customBackgroundRGB
        self.obsBackgroundMode = obsBackgroundMode
        self.obsCustomBackgroundRGB = obsCustomBackgroundRGB
        self.selectedCameraID = selectedCameraID
        self.selectedMicID = selectedMicID
        self.alwaysOnTop = alwaysOnTop
    }
}

public struct PerAvatarPreferences: Codable, Sendable, Equatable {
    public var cameraZoom: Float
    public var cameraPanX: Float
    public var cameraPanY: Float
    public var inputMode: TrackingInputMode
    public var cameraTrackingMode: CameraTrackingMode
    public var faceTrackingEnabled: Bool
    public var handTrackingEnabled: Bool
    public var mirrorHands: Bool
    public var micLipSyncEnabled: Bool
    public var faceSensitivity: Double
    public var headSmoothing: Double
    public var handSensitivity: Double
    public var handSmoothing: Double
    public var autoExpressionTracking: Bool
    public var lipSyncGain: Double
    public var lipSyncThreshold: Double
    public var physicsEnabled: Bool
    public var physicsIntensity: Double
    public var breastPhysicsLevel: BreastPhysicsLevel
    public var categoryPhysicsMultipliers: [String: Double]
    public var dragReactionsEnabled: Bool
    public var animationsEnabled: Bool
    public var effectsEnabled: Bool
    public var activeExpressionId: String?

    public init(
        cameraZoom: Float = 1.0,
        cameraPanX: Float = 0.0,
        cameraPanY: Float = 0.0,
        inputMode: TrackingInputMode = .hybrid,
        cameraTrackingMode: CameraTrackingMode = .faceOnly,
        faceTrackingEnabled: Bool = false,
        handTrackingEnabled: Bool = false,
        mirrorHands: Bool = true,
        micLipSyncEnabled: Bool = false,
        faceSensitivity: Double = 1.0,
        headSmoothing: Double = 0.45,
        handSensitivity: Double = 1.0,
        handSmoothing: Double = 0.36,
        autoExpressionTracking: Bool = true,
        lipSyncGain: Double = 1.6,
        lipSyncThreshold: Double = 0.032,
        physicsEnabled: Bool = true,
        physicsIntensity: Double = 1.0,
        breastPhysicsLevel: BreastPhysicsLevel = .normal,
        categoryPhysicsMultipliers: [String: Double] = [:],
        dragReactionsEnabled: Bool = true,
        animationsEnabled: Bool = true,
        effectsEnabled: Bool = true,
        activeExpressionId: String? = nil
    ) {
        self.cameraZoom = cameraZoom
        self.cameraPanX = cameraPanX
        self.cameraPanY = cameraPanY
        self.inputMode = inputMode
        self.cameraTrackingMode = cameraTrackingMode
        self.faceTrackingEnabled = faceTrackingEnabled
        self.handTrackingEnabled = handTrackingEnabled
        self.mirrorHands = mirrorHands
        self.micLipSyncEnabled = micLipSyncEnabled
        self.faceSensitivity = faceSensitivity
        self.headSmoothing = headSmoothing
        self.handSensitivity = handSensitivity
        self.handSmoothing = handSmoothing
        self.autoExpressionTracking = autoExpressionTracking
        self.lipSyncGain = lipSyncGain
        self.lipSyncThreshold = lipSyncThreshold
        self.physicsEnabled = physicsEnabled
        self.physicsIntensity = physicsIntensity
        self.breastPhysicsLevel = breastPhysicsLevel
        self.categoryPhysicsMultipliers = categoryPhysicsMultipliers
        self.dragReactionsEnabled = dragReactionsEnabled
        self.animationsEnabled = animationsEnabled
        self.effectsEnabled = effectsEnabled
        self.activeExpressionId = activeExpressionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cameraZoom = try c.decodeIfPresent(Float.self, forKey: .cameraZoom) ?? 1.0
        self.cameraPanX = try c.decodeIfPresent(Float.self, forKey: .cameraPanX) ?? 0.0
        self.cameraPanY = try c.decodeIfPresent(Float.self, forKey: .cameraPanY) ?? 0.0
        self.inputMode = try c.decodeIfPresent(TrackingInputMode.self, forKey: .inputMode) ?? .hybrid
        self.cameraTrackingMode = try c.decodeIfPresent(CameraTrackingMode.self, forKey: .cameraTrackingMode) ?? .faceOnly
        self.faceTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .faceTrackingEnabled) ?? false
        self.handTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .handTrackingEnabled) ?? false
        self.mirrorHands = try c.decodeIfPresent(Bool.self, forKey: .mirrorHands) ?? true
        self.micLipSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .micLipSyncEnabled) ?? false
        self.faceSensitivity = try c.decodeIfPresent(Double.self, forKey: .faceSensitivity) ?? 1.0
        self.headSmoothing = try c.decodeIfPresent(Double.self, forKey: .headSmoothing) ?? 0.45
        self.handSensitivity = try c.decodeIfPresent(Double.self, forKey: .handSensitivity) ?? 1.0
        self.handSmoothing = try c.decodeIfPresent(Double.self, forKey: .handSmoothing) ?? 0.36
        self.autoExpressionTracking = try c.decodeIfPresent(Bool.self, forKey: .autoExpressionTracking) ?? true
        self.lipSyncGain = try c.decodeIfPresent(Double.self, forKey: .lipSyncGain) ?? 1.6
        self.lipSyncThreshold = try c.decodeIfPresent(Double.self, forKey: .lipSyncThreshold) ?? 0.032
        self.physicsEnabled = try c.decodeIfPresent(Bool.self, forKey: .physicsEnabled) ?? true
        self.physicsIntensity = try c.decodeIfPresent(Double.self, forKey: .physicsIntensity) ?? 1.0
        self.breastPhysicsLevel = try c.decodeIfPresent(BreastPhysicsLevel.self, forKey: .breastPhysicsLevel) ?? .normal
        self.categoryPhysicsMultipliers = try c.decodeIfPresent([String: Double].self, forKey: .categoryPhysicsMultipliers) ?? [:]
        self.dragReactionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .dragReactionsEnabled) ?? true
        self.animationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? true
        self.effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        self.activeExpressionId = try c.decodeIfPresent(String.self, forKey: .activeExpressionId)
    }
}

public struct AvatarLibraryEntry: Identifiable, Hashable, Sendable {
    public var id: String { url.standardizedFileURL.path }
    public let url: URL
    public let displayName: String
    public let sourceLabel: String

    public init(url: URL, displayName: String, sourceLabel: String) {
        self.url = url.standardizedFileURL
        self.displayName = displayName
        self.sourceLabel = sourceLabel
    }
}

@MainActor
public final class PreferencesStore {
    private let defaults: UserDefaults
    private let globalKey = "SVStudio.GlobalPreferences.v1"
    private let avatarMapKey = "SVStudio.AvatarPreferences.v1"
    private let legacyGlobalKey = "Satella.GlobalPreferences.v1"
    private let legacyAvatarMapKey = "Satella.AvatarPreferences.v1"

    public private(set) var global: GlobalPreferences
    private var avatarPrefs: [String: PerAvatarPreferences]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: globalKey) ?? defaults.data(forKey: legacyGlobalKey),
           let decoded = try? JSONDecoder().decode(GlobalPreferences.self, from: data) {
            self.global = decoded
            if defaults.data(forKey: globalKey) == nil {
                defaults.set(data, forKey: globalKey)
            }
        } else {
            self.global = GlobalPreferences()
        }
        if let data = defaults.data(forKey: avatarMapKey) ?? defaults.data(forKey: legacyAvatarMapKey),
           let decoded = try? JSONDecoder().decode([String: PerAvatarPreferences].self, from: data) {
            self.avatarPrefs = decoded
            if defaults.data(forKey: avatarMapKey) == nil {
                defaults.set(data, forKey: avatarMapKey)
            }
        } else {
            self.avatarPrefs = [:]
        }
        ensureLibraryDirectoryExists()
    }

    public var userLibraryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("SVStudio/Avatars", isDirectory: true)
    }

    private var legacyLibraryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Satella/Avatars", isDirectory: true)
    }

    public func ensureLibraryDirectoryExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: userLibraryDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: legacyLibraryDirectory.path),
           let items = try? fm.contentsOfDirectory(at: legacyLibraryDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in items where item.pathExtension.lowercased() == "sat" {
                let dest = userLibraryDirectory.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.copyItem(at: item, to: dest)
                }
            }
        }
    }

    public func saveGlobal(_ updated: GlobalPreferences) {
        self.global = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: globalKey)
        }
    }

    public func updateGlobal(_ mutate: (inout GlobalPreferences) -> Void) {
        var copy = global
        mutate(&copy)
        saveGlobal(copy)
    }

    public func preferences(forAvatarKey key: String) -> PerAvatarPreferences {
        avatarPrefs[key] ?? PerAvatarPreferences()
    }

    public func savePreferences(_ prefs: PerAvatarPreferences, forAvatarKey key: String) {
        avatarPrefs[key] = prefs
        if let data = try? JSONEncoder().encode(avatarPrefs) {
            defaults.set(data, forKey: avatarMapKey)
        }
    }

    public func recordLoadedAvatar(url: URL) {
        let path = url.standardizedFileURL.path
        var next = global
        next.lastAvatarPath = path
        next.recentAvatarPaths.removeAll { $0 == path }
        next.recentAvatarPaths.insert(path, at: 0)
        if next.recentAvatarPaths.count > 12 {
            next.recentAvatarPaths = Array(next.recentAvatarPaths.prefix(12))
        }
        saveGlobal(next)
    }

    /// Dynamically discovers `.sat` avatars across the bundled app resources, workspace Avatars folder, User Library, and recents.
    public func discoverAvatars() -> [AvatarLibraryEntry] {
        var seenPaths = Set<String>()
        var seenBundledNames = Set<String>()
        var results: [AvatarLibraryEntry] = []

        func scanDirectory(_ dir: URL, sourceLabel: String) {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return }
            let sorted = items
                .filter { $0.pathExtension.lowercased() == "sat" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for item in sorted {
                let p = item.standardizedFileURL.path
                let fileKey = item.lastPathComponent.lowercased()
                if sourceLabel == "Bundled" && !seenBundledNames.insert(fileKey).inserted {
                    continue
                }
                if seenPaths.insert(p).inserted {
                    results.append(AvatarLibraryEntry(
                        url: item,
                        displayName: item.deletingPathExtension().lastPathComponent,
                        sourceLabel: sourceLabel
                    ))
                }
            }
        }

        // 1. App bundle Resources/Avatars (if packaged in .app)
        if let resURL = Bundle.main.resourceURL {
            scanDirectory(resURL.appendingPathComponent("Avatars", isDirectory: true), sourceLabel: "Bundled")
        }

        // 2. Sibling Avatars folder relative to executable (both .app/Contents/MacOS/Satella -> ../../Avatars and Source/.build/...)
        let execURL = URL(fileURLWithPath: CommandLine.arguments.first ?? Bundle.main.bundlePath).standardizedFileURL
        var cursor = execURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = cursor.appendingPathComponent("Avatars", isDirectory: true)
            scanDirectory(candidate, sourceLabel: "Bundled")
            cursor = cursor.deletingLastPathComponent()
        }

        // 3. User Application Support Library (~/Library/Application Support/SVStudio/Avatars + legacy Satella/Avatars)
        scanDirectory(userLibraryDirectory, sourceLabel: "Library")
        scanDirectory(legacyLibraryDirectory, sourceLabel: "Library")

        // 4. Recent custom files (avoid listing bundled copies a second time if already discovered above)
        let bundledCanonPaths = Set(results.filter { $0.sourceLabel == "Bundled" }.map { $0.url.lastPathComponent.lowercased() })
        for path in global.recentAvatarPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path),
               url.pathExtension.lowercased() == "sat",
               !bundledCanonPaths.contains(url.lastPathComponent.lowercased()) || (!url.path.contains("/Satella/") && !url.path.contains("/SVStudio/")),
               seenPaths.insert(url.path).inserted {
                results.append(AvatarLibraryEntry(
                    url: url,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    sourceLabel: "Recent"
                ))
            }
        }
        return results
    }
}
