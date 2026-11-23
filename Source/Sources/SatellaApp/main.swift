import Foundation
import AppKit
import SwiftUI
import SatellaCore
import SatellaRender

// Supports CLI smoke check mode for headless verification (`Satella --smoke-check [--avatar path.sat]`)
if CommandLine.arguments.contains("--smoke-check") {
    @MainActor func runSmokeCheck() -> Int32 {
        do {
            let store = PreferencesStore()
            let controller = AppController(preferencesStore: store)
            guard let engine = controller.renderEngine else {
                fputs("ERROR: RenderEngine failed to initialize\n", stderr)
                return 2
            }

            if let idx = CommandLine.arguments.firstIndex(of: "--avatar"), idx + 1 < CommandLine.arguments.count {
                let avatarURL = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
                controller.loadAvatar(url: avatarURL)
                guard let avatar = controller.loadedAvatar else {
                    fputs("ERROR: Failed to load avatar \(avatarURL.path): \(controller.errorMessage ?? "unknown")\n", stderr)
                    return 3
                }
                controller.stepSimulationForCurrentFrame(now: CACurrentMediaTime() + 0.016)
                guard let snap = controller.currentMainFrameSnapshot() else {
                    fputs("ERROR: No frame snapshot generated\n", stderr)
                    return 4
                }
                let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("satella_app_smoke.png")
                try engine.renderOffscreenToPNG(
                    avatar: avatar,
                    drawables: snap.drawables,
                    effects: snap.effects,
                    width: 480,
                    height: 640,
                    camera: snap.camera,
                    background: .greenScreen,
                    outputURL: outURL
                )
                // Also verify zero-copy IOSurface CVPixelBuffer render used by VirtualWebcamManager
                let pbAttrs: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 640,
                    kCVPixelBufferHeightKey as String: 480,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]
                var pbOpt: CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA, pbAttrs as CFDictionary, &pbOpt) == kCVReturnSuccess,
                      let pb = pbOpt else {
                    fputs("ERROR: Failed to create IOSurface CVPixelBuffer\n", stderr)
                    return 6
                }
                try engine.renderFrame(
                    into: pb,
                    canvasSize: snap.canvasSize,
                    camera: snap.camera,
                    drawables: snap.drawables,
                    effects: snap.effects,
                    background: .black
                )
                print("App smoke-check loaded \(avatar.manifest.name), rendered \(outURL.path) + VirtualCam IOSurface PB (640x480), drawables=\(snap.drawables.count)")
            }

            // Verify invalid `.sat` fails gracefully without clearing loaded state
            let previousName = controller.loadedAvatar?.manifest.name
            let badURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("corrupt_test.sat")
            try Data("NOT_A_ZIP_ARCHIVE".utf8).write(to: badURL)
            controller.loadAvatar(url: badURL)
            guard controller.errorMessage != nil, controller.loadedAvatar?.manifest.name == previousName else {
                fputs("ERROR: Corrupt .sat did not preserve state or report error cleanly\n", stderr)
                return 5
            }
            print("Corrupt .sat error safety verified: \(controller.errorMessage ?? "")")

            print("Discovered cameras=\(controller.availableCameras.count), mics=\(controller.availableMics.count), webcamSinks=\(controller.availableWebcamSinks.count), libraryAvatars=\(controller.libraryEntries.count)")
            print("SATELLA_APP_SMOKE_PASS")
            return 0
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
    let code = MainActor.assumeIsolated { runSmokeCheck() }
    exit(code)
}

@MainActor
final class SatellaAppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBar()
        createAndShowMainWindow()

        // If Finder passed `.sat` on launch args, open it; otherwise restore last avatar
        let fileArgs = CommandLine.arguments.dropFirst().filter {
            !$0.hasPrefix("-") && $0.lowercased().hasSuffix(".sat") && FileManager.default.fileExists(atPath: $0)
        }
        if let firstFile = fileArgs.first {
            controller.loadAvatar(url: URL(fileURLWithPath: firstFile))
        } else {
            controller.restoreLastOrDefaultAvatar()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let sat = urls.first(where: { $0.pathExtension.lowercased() == "sat" }) {
            controller.loadAvatar(url: sat)
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.virtualWebcam.stop()
        controller.faceTracker.stop()
        controller.lipSync.stop()
        controller.persistCurrentAvatarPreferences()
    }

    private func createAndShowMainWindow() {
        let rootView = SatellaMainView(controller: controller)
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(
            contentRect: NSRect(x: 120, y: 90, width: 1180, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SVStudio"
        win.contentViewController = hosting
        win.minSize = NSSize(width: 920, height: 620)
        win.level = controller.alwaysOnTop ? .floating : .normal
        win.center()
        win.makeKeyAndOrderFront(nil)
        self.mainWindow = win
    }

    private func setupMenuBar() {
        let menuBar = NSMenu()
        NSApp.mainMenu = menuBar

        // App Menu
        let appMenuItem = NSMenuItem()
        menuBar.addItem(appMenuItem)
        let appMenu = NSMenu(title: "SVStudio")
        appMenu.addItem(withTitle: "About SVStudio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide SVStudio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit SVStudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File Menu
        let fileMenuItem = NSMenuItem()
        menuBar.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open Avatar (.sat)...", action: #selector(menuOpenAvatar), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let importItem = NSMenuItem(title: "Import Avatar to Library...", action: #selector(menuImportAvatar), keyEquivalent: "i")
        importItem.keyEquivalentModifierMask = [.command, .shift]
        importItem.target = self
        fileMenu.addItem(importItem)

        fileMenu.addItem(.separator())
        let libItem = NSMenuItem(title: "Open Avatars Folder in Finder", action: #selector(menuOpenLibraryFolder), keyEquivalent: "")
        libItem.target = self
        fileMenu.addItem(libItem)
        fileMenuItem.submenu = fileMenu

        // View Menu
        let viewMenuItem = NSMenuItem()
        menuBar.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        let resetCam = NSMenuItem(title: "Reset Avatar Framing", action: #selector(menuResetCamera), keyEquivalent: "0")
        resetCam.target = self
        viewMenu.addItem(resetCam)

        let upperItem = NSMenuItem(title: "Fit Upper Body", action: #selector(menuFitUpper), keyEquivalent: "1")
        upperItem.target = self
        viewMenu.addItem(upperItem)

        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(menuToggleSidebar), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        sidebarItem.target = self
        viewMenu.addItem(sidebarItem)

        viewMenu.addItem(.separator())
        let obsItem = NSMenuItem(title: "Toggle OBS Clean Output Window", action: #selector(menuToggleOBS), keyEquivalent: "b")
        obsItem.keyEquivalentModifierMask = [.command, .shift]
        obsItem.target = self
        viewMenu.addItem(obsItem)
        viewMenuItem.submenu = viewMenu
    }

    @objc private func menuOpenAvatar() { controller.openAvatarPicker() }
    @objc private func menuImportAvatar() { controller.importAvatarPicker() }
    @objc private func menuOpenLibraryFolder() { controller.openLibraryFolderInFinder() }
    @objc private func menuResetCamera() { controller.resetCamera() }
    @objc private func menuFitUpper() { controller.fitUpperBodyPreset() }
    @objc private func menuToggleSidebar() { controller.toggleSidebar() }
    @objc private func menuToggleOBS() { controller.toggleOBSWindow() }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { SatellaAppDelegate() }
MainActor.assumeIsolated {
    app.delegate = delegate
}
app.run()
