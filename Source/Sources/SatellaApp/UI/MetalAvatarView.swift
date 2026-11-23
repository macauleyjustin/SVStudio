import Foundation
import AppKit
import SwiftUI
import Metal
import MetalKit
import UniformTypeIdentifiers
import SatellaCore
import SatellaRender

public struct SatellaMetalViewport: NSViewRepresentable {
    public let renderEngine: RenderEngine
    public let snapshotProvider: FrameSnapshotProvider
    public var camera: SatCameraTransform
    public var isTransparentWindow: Bool
    public var onCameraChanged: (SatCameraTransform) -> Void
    public var onResetCamera: () -> Void
    public var onDropSatFile: (URL) -> Void
    public var onDragMotion: ((Double, Double, Bool) -> Void)?

    public init(
        renderEngine: RenderEngine,
        snapshotProvider: FrameSnapshotProvider,
        camera: SatCameraTransform,
        isTransparentWindow: Bool,
        onCameraChanged: @escaping (SatCameraTransform) -> Void,
        onResetCamera: @escaping () -> Void,
        onDropSatFile: @escaping (URL) -> Void,
        onDragMotion: ((Double, Double, Bool) -> Void)? = nil
    ) {
        self.renderEngine = renderEngine
        self.snapshotProvider = snapshotProvider
        self.camera = camera
        self.isTransparentWindow = isTransparentWindow
        self.onCameraChanged = onCameraChanged
        self.onResetCamera = onResetCamera
        self.onDropSatFile = onDropSatFile
        self.onDragMotion = onDragMotion
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(renderEngine: renderEngine, snapshotProvider: snapshotProvider)
    }

    public func makeNSView(context: Context) -> InteractiveMTKView {
        let view = InteractiveMTKView(frame: .zero, device: renderEngine.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.layer?.isOpaque = !isTransparentWindow
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        view.camera = camera
        view.onCameraChanged = onCameraChanged
        view.onResetCamera = onResetCamera
        view.onDropSatFile = onDropSatFile
        view.onDragMotion = onDragMotion
        return view
    }

    public func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        nsView.camera = camera
        nsView.onCameraChanged = onCameraChanged
        nsView.onResetCamera = onResetCamera
        nsView.onDropSatFile = onDropSatFile
        nsView.onDragMotion = onDragMotion
        nsView.layer?.isOpaque = !isTransparentWindow
        nsView.window?.isOpaque = !isTransparentWindow
        if isTransparentWindow {
            nsView.window?.backgroundColor = .clear
        }
    }

    @MainActor
    public final class Coordinator: NSObject, MTKViewDelegate {
        private let renderEngine: RenderEngine
        private weak var snapshotProvider: FrameSnapshotProvider?
        private var lastStepTime: CFTimeInterval = CACurrentMediaTime()
        private var fpsSampleStart: CFTimeInterval = CACurrentMediaTime()
        private var frameCounter: Int = 0
        private var accumulatedMs: Double = 0.0

        init(renderEngine: RenderEngine, snapshotProvider: FrameSnapshotProvider) {
            self.renderEngine = renderEngine
            self.snapshotProvider = snapshotProvider
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let provider = snapshotProvider else { return }
            let t0 = CACurrentMediaTime()
            provider.stepSimulationForCurrentFrame(now: t0)

            guard let snapshot = provider.currentMainFrameSnapshot(),
                  let drawable = view.currentDrawable,
                  let cmdBuf = renderEngine.commandQueue.makeCommandBuffer() else {
                return
            }

            let vpW = max(1, Int(view.drawableSize.width))
            let vpH = max(1, Int(view.drawableSize.height))
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

            let elapsedMs = (CACurrentMediaTime() - t0) * 1000.0
            accumulatedMs += elapsedMs
            frameCounter += 1
            let span = t0 - fpsSampleStart
            if span >= 0.5 {
                let fps = Double(frameCounter) / span
                let avgMs = accumulatedMs / Double(frameCounter)
                provider.reportMainViewportMetrics(fps: fps, frameMs: avgMs)
                frameCounter = 0
                accumulatedMs = 0.0
                fpsSampleStart = t0
            }
            lastStepTime = t0
        }
    }
}

public final class InteractiveMTKView: MTKView {
    public var camera = SatCameraTransform()
    public var onCameraChanged: ((SatCameraTransform) -> Void)?
    public var onResetCamera: (() -> Void)?
    public var onDropSatFile: ((URL) -> Void)?
    public var onDragMotion: ((Double, Double, Bool) -> Void)?

    private var dragStartPoint: NSPoint?
    private var lastDragPoint: NSPoint?
    private var dragStartPan: (x: Float, y: Float) = (0, 0)
    private var pinchStartZoom: Float = 1.0

    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        setupInteraction()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupInteraction()
    }

    private func setupInteraction() {
        registerForDraggedTypes([.fileURL])
        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnify)
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onResetCamera?()
            return
        }
        let pt = convert(event.locationInWindow, from: nil)
        dragStartPoint = pt
        lastDragPoint = pt
        dragStartPan = (camera.panX, camera.panY)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        let scale = Float(drawableSize.width / max(1.0, bounds.width))
        let dxPx = Float(cur.x - start.x) * scale
        let dyPx = -Float(cur.y - start.y) * scale
        let prev = lastDragPoint ?? start
        let stepDx = Double(cur.x - prev.x) * Double(scale)
        let stepDy = -Double(cur.y - prev.y) * Double(scale)
        lastDragPoint = cur
        onDragMotion?(stepDx, stepDy, true)
        var updated = camera
        updated.panX = max(-3600.0, min(3600.0, dragStartPan.x + dxPx))
        updated.panY = max(-3600.0, min(3600.0, dragStartPan.y + dyPx))
        camera = updated
        onCameraChanged?(updated)
    }

    public override func mouseUp(with event: NSEvent) {
        if dragStartPoint != nil {
            onDragMotion?(0.0, 0.0, false)
        }
        dragStartPoint = nil
        lastDragPoint = nil
    }

    public override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        guard abs(delta) > 0.001 else { return }
        let factor = exp(delta * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04))
        applyZoom(factor: factor, locationInView: convert(event.locationInWindow, from: nil))
    }

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        if gesture.state == .began {
            pinchStartZoom = camera.zoom
        } else if gesture.state == .changed || gesture.state == .ended {
            let clampedNew = max(0.25, min(6.0, pinchStartZoom * Float(1.0 + gesture.magnification)))
            let ratio = clampedNew / max(0.01, camera.zoom)
            let pt = gesture.location(in: self)
            applyZoomTarget(newZoom: clampedNew, ratio: ratio, locationInView: pt)
        }
    }

    private func applyZoom(factor: Float, locationInView pt: NSPoint) {
        let clampedNew = max(0.25, min(6.0, camera.zoom * factor))
        let ratio = clampedNew / max(0.01, camera.zoom)
        applyZoomTarget(newZoom: clampedNew, ratio: ratio, locationInView: pt)
    }

    private func applyZoomTarget(newZoom: Float, ratio: Float, locationInView pt: NSPoint) {
        let scaleX = Float(drawableSize.width / max(1.0, bounds.width))
        let scaleY = Float(drawableSize.height / max(1.0, bounds.height))
        let cxPx = Float(pt.x) * scaleX
        let cyPx = Float(bounds.height - pt.y) * scaleY
        let vw = Float(max(1.0, drawableSize.width))
        let vh = Float(max(1.0, drawableSize.height))

        var updated = camera
        updated.panX = max(-3600.0, min(3600.0, (cxPx - vw * 0.5) * (1.0 - ratio) + updated.panX * ratio))
        updated.panY = max(-3600.0, min(3600.0, (cyPx - vh * 0.5) * (1.0 - ratio) + updated.panY * ratio))
        updated.zoom = newZoom
        camera = updated
        onCameraChanged?(updated)
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractFirstSatURL(from: sender) != nil {
            return .copy
        }
        return []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = extractFirstSatURL(from: sender) else { return false }
        onDropSatFile?(url)
        return true
    }

    private func extractFirstSatURL(from info: NSDraggingInfo) -> URL? {
        guard let objs = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        return objs.first { $0.pathExtension.lowercased() == "sat" }
    }
}
