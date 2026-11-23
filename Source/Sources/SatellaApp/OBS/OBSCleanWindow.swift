import Foundation
import AppKit
import Metal
import MetalKit
import SatellaCore
import SatellaRender

@MainActor
public final class OBSCleanWindowController: NSObject, NSWindowDelegate, MTKViewDelegate {
    private let renderEngine: RenderEngine
    private weak var snapshotSource: FrameSnapshotProvider?
    private var window: NSWindow?
    private var mtkView: MTKView?
    public var onWindowClosed: (() -> Void)?

    public init(renderEngine: RenderEngine, snapshotSource: FrameSnapshotProvider) {
        self.renderEngine = renderEngine
        self.snapshotSource = snapshotSource
        super.init()
    }

    public var isOpen: Bool {
        window?.isVisible ?? false
    }

    public func openWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rect = NSRect(x: 160, y: 140, width: 960, height: 1080)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "SVStudio OBS Output"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.isOpaque = false
        win.backgroundColor = .clear

        let view = MTKView(frame: rect, device: renderEngine.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = self
        view.autoresizingMask = [.width, .height]

        win.contentView = view
        win.makeKeyAndOrderFront(nil)

        self.mtkView = view
        self.window = win
    }

    public func closeWindow() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        mtkView?.isPaused = true
        window = nil
        mtkView = nil
        onWindowClosed?()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let source = snapshotSource,
              let snapshot = source.currentOBSFrameSnapshot(),
              let drawable = view.currentDrawable,
              let cmdBuf = renderEngine.commandQueue.makeCommandBuffer() else {
            return
        }

        let vpW = max(1, Int(view.drawableSize.width))
        let vpH = max(1, Int(view.drawableSize.height))
        let isOpaque = snapshot.background != .transparent
        view.layer?.isOpaque = isOpaque
        window?.isOpaque = isOpaque

        renderEngine.encodeFrame(
            into: cmdBuf,
            targetTexture: drawable.texture,
            viewportWidth: vpW,
            viewportHeight: vpH,
            canvasSize: snapshot.canvasSize,
            camera: snapshot.camera,
            drawables: snapshot.drawables,
            effects: snapshot.effects,
            background: snapshot.background,
            customColor: snapshot.customColor
        )
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}

public struct LiveRenderSnapshot: @unchecked Sendable {
    public let canvasSize: SatCanvas
    public let camera: SatCameraTransform
    public let drawables: [EvaluatedDrawable]
    public let effects: [EffectsRenderGroup]
    public let background: SatBackgroundMode
    public let customColor: SIMD3<Float>
}

@MainActor
public protocol FrameSnapshotProvider: AnyObject {
    func currentMainFrameSnapshot() -> LiveRenderSnapshot?
    func currentOBSFrameSnapshot() -> LiveRenderSnapshot?
    func stepSimulationForCurrentFrame(now: CFTimeInterval)
    func reportMainViewportMetrics(fps: Double, frameMs: Double)
}
