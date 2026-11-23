import Foundation
import Metal
import simd
import CoreGraphics
import CoreVideo
import IOSurface
import ImageIO
import SatellaCore

public enum SatBackgroundMode: String, Codable, CaseIterable, Sendable {
    case black = "Black"
    case greenScreen = "Green Screen"
    case white = "White"
    case checkerboard = "Checkerboard"
    case transparent = "Transparent"
    case custom = "Custom"
}

public struct SatCameraTransform: Codable, Sendable, Equatable {
    public var zoom: Float = 1.0
    public var panX: Float = 0.0
    public var panY: Float = 0.0

    public init(zoom: Float = 1.0, panX: Float = 0.0, panY: Float = 0.0) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
    }
}

private struct GpuMeshVertex {
    var pos: SIMD2<Float>
    var uv: SIMD2<Float>
    var uvClip: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct GpuEffectVertex {
    var pos: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct GpuUniforms {
    var toNDC: SIMD4<Float> // (sx, sy, ox, oy) -> ndc = pos * xy + zw
    var params: SIMD4<Float> // (useMask, invertedMask, effectMode, time)
}

public enum SatRenderError: Error, LocalizedError {
    case noMetalDevice
    case shaderCompileFailed(String)
    case textureDecodeFailed(String)
    case readbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice: return "No Metal GPU device available on this system."
        case .shaderCompileFailed(let msg): return "Metal shader compilation failed: \(msg)"
        case .textureDecodeFailed(let file): return "Failed to decode texture PNG '\(file)'."
        case .readbackFailed(let msg): return "Offscreen GPU frame readback failed: \(msg)"
        }
    }
}

public final class RenderEngine: @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    private let meshPipelineNormal: MTLRenderPipelineState
    private let meshPipelineAdditive: MTLRenderPipelineState
    private let meshPipelineMultiply: MTLRenderPipelineState
    private let meshPipelineScreen: MTLRenderPipelineState
    private let maskPipeline: MTLRenderPipelineState
    private let effectPipelineAlpha: MTLRenderPipelineState
    private let effectPipelineAdditive: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var textures: [String: MTLTexture] = [:]
    private var offscreenSceneTex: MTLTexture?
    private var maskTex: MTLTexture?
    private var offscreenW: Int = 0
    private var offscreenH: Int = 0

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 toNDC;  // sx, sy, ox, oy
        float4 params; // useMask, invertedMask, backgroundMode, time
    };

    struct MeshIn {
        float2 pos;
        float2 uv;
        float4 uvClip;
        float4 color;
    };

    struct MeshOut {
        float4 position [[position]];
        float2 uv;
        float4 uvClip;
        float4 color;
        float2 screenUV;
    };

    vertex MeshOut vs_mesh(uint vid [[vertex_id]],
                           const device MeshIn *verts [[buffer(0)]],
                           constant Uniforms &u [[buffer(1)]]) {
        MeshIn v = verts[vid];
        float2 ndc = float2(v.pos.x * u.toNDC.x + u.toNDC.z,
                            v.pos.y * u.toNDC.y + u.toNDC.w);
        MeshOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = v.uv;
        out.uvClip = v.uvClip;
        out.color = v.color;
        out.screenUV = float2((ndc.x + 1.0) * 0.5, (1.0 - ndc.y) * 0.5);
        return out;
    }

    fragment float4 fs_mesh(MeshOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            texture2d<float> maskTex [[texture(1)]],
                            sampler samp [[sampler(0)]],
                            constant Uniforms &u [[buffer(1)]]) {
        if (in.uv.x < in.uvClip.x || in.uv.y < in.uvClip.y ||
            in.uv.x > in.uvClip.z || in.uv.y > in.uvClip.w) {
            discard_fragment();
        }
        float4 t = tex.sample(samp, in.uv);
        // Texture is straight-alpha RGBA with edge color bleed: convert cleanly AFTER bilinear filtering!
        float alpha = t.a * in.color.a;
        if (u.params.x > 0.5) {
            float m = maskTex.sample(samp, in.screenUV).r;
            if (u.params.y > 0.5) {
                m = 1.0 - m;
            }
            alpha *= m;
        }
        if (alpha <= 0.0005) {
            discard_fragment();
        }
        float3 rgb = t.rgb * in.color.rgb * alpha;
        return float4(rgb, alpha);
    }

    fragment float4 fs_mask(MeshOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            sampler samp [[sampler(0)]]) {
        if (in.uv.x < in.uvClip.x || in.uv.y < in.uvClip.y ||
            in.uv.x > in.uvClip.z || in.uv.y > in.uvClip.w) {
            discard_fragment();
        }
        float a = tex.sample(samp, in.uv).a * in.color.a;
        return float4(a, 0.0, 0.0, 1.0);
    }

    struct EffectIn {
        float2 pos;
        float2 uv;
        float4 color;
    };

    struct EffectOut {
        float4 position [[position]];
        float2 uv;
        float2 worldPos;
        float4 color;
    };

    inline float sat_hash2(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    inline float sat_noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = sat_hash2(i);
        float b = sat_hash2(i + float2(1.0, 0.0));
        float c = sat_hash2(i + float2(0.0, 1.0));
        float d = sat_hash2(i + float2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    inline float sat_fbm(float2 p) {
        float v = 0.0;
        float amp = 0.5;
        for (int k = 0; k < 3; k++) {
            v += amp * sat_noise(p);
            p = p * 2.03 + float2(17.1, 31.7);
            amp *= 0.5;
        }
        return v;
    }

    vertex EffectOut vs_effect(uint vid [[vertex_id]],
                               const device EffectIn *verts [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
        EffectIn v = verts[vid];
        float2 ndc = float2(v.pos.x * u.toNDC.x + u.toNDC.z,
                            v.pos.y * u.toNDC.y + u.toNDC.w);
        EffectOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = v.uv;
        out.worldPos = v.pos;
        out.color = v.color;
        return out;
    }

    fragment float4 fs_effect(EffectOut in [[stage_in]]) {
        float2 d = in.uv * 2.0 - 1.0;
        float r2 = dot(d, d);
        if (r2 >= 1.0) { discard_fragment(); }
        float envelope = pow(max(0.0, 1.0 - r2), 2.1);
        float smoke = 0.52 + 0.72 * sat_fbm(in.worldPos * 0.022 + d * 1.1);
        float a = saturate(in.color.a * envelope * smoke);
        return float4(in.color.rgb * a, a);
    }

    struct QuadOut {
        float4 position [[position]];
        float2 uv;
        float2 px;
    };

    vertex QuadOut vs_fullscreen(uint vid [[vertex_id]], constant Uniforms &u [[buffer(1)]]) {
        const float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        const float2 uvs[3] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        QuadOut out;
        out.position = float4(pos[vid], 0.0, 1.0);
        out.uv = uvs[vid];
        out.px = (pos[vid] * float2(0.5, -0.5) + 0.5) * u.toNDC.xy;
        return out;
    }

    fragment float4 fs_composite(QuadOut in [[stage_in]],
                                 texture2d<float> sceneTex [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant Uniforms &u [[buffer(1)]]) {
        float4 fg = sceneTex.sample(samp, in.uv);
        // u.toNDC.zw carries custom rgb; u.params.x carries bgMode (0=black,1=green,2=white,3=checker,4=transparent,5=custom)
        float mode = u.params.x;
        float4 bg = float4(0.0, 0.0, 0.0, 1.0);
        if (mode > 0.5 && mode < 1.5) {
            bg = float4(0.0, 1.0, 0.0, 1.0);
        } else if (mode > 1.5 && mode < 2.5) {
            bg = float4(1.0, 1.0, 1.0, 1.0);
        } else if (mode > 2.5 && mode < 3.5) {
            int cx = int(floor(in.px.x / 20.0));
            int cy = int(floor(in.px.y / 20.0));
            float chk = ((cx + cy) & 1) == 0 ? 0.84 : 0.66;
            bg = float4(chk, chk, chk, 1.0);
        } else if (mode > 3.5 && mode < 4.5) {
            // Transparent PNG readback: un-premultiply clean straight RGBA
            float a = clamp(fg.a, 0.0, 1.0);
            float3 straight = a > 0.0005 ? clamp(fg.rgb / a, 0.0, 1.0) : float3(0.0);
            return float4(straight, a);
        } else if (mode > 4.5) {
            bg = float4(u.toNDC.z, u.toNDC.w, u.params.y, 1.0);
        }
        float3 blended = fg.rgb + bg.rgb * (1.0 - fg.a);
        return float4(saturate(blended), 1.0);
    }
    """

    public init(device: MTLDevice? = nil) throws {
        guard let dev = device ?? MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            throw SatRenderError.noMetalDevice
        }
        self.device = dev
        self.commandQueue = queue

        let lib: MTLLibrary
        do {
            lib = try dev.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw SatRenderError.shaderCompileFailed(error.localizedDescription)
        }

        let vsMesh = lib.makeFunction(name: "vs_mesh")!
        let fsMesh = lib.makeFunction(name: "fs_mesh")!
        let fsMask = lib.makeFunction(name: "fs_mask")!
        let vsEffect = lib.makeFunction(name: "vs_effect")!
        let fsEffect = lib.makeFunction(name: "fs_effect")!
        let vsFull = lib.makeFunction(name: "vs_fullscreen")!
        let fsComp = lib.makeFunction(name: "fs_composite")!

        func makeMeshPSO(_ blend: SatBlendMode) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vsMesh
            desc.fragmentFunction = fsMesh
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            switch blend {
            case .normal:
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            case .additive:
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .one
            case .multiply:
                desc.colorAttachments[0].sourceRGBBlendFactor = .destinationColor
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            case .screen:
                desc.colorAttachments[0].sourceRGBBlendFactor = .oneMinusDestinationColor
                desc.colorAttachments[0].destinationRGBBlendFactor = .one
            }
            return try dev.makeRenderPipelineState(descriptor: desc)
        }

        self.meshPipelineNormal = try makeMeshPSO(.normal)
        self.meshPipelineAdditive = try makeMeshPSO(.additive)
        self.meshPipelineMultiply = try makeMeshPSO(.multiply)
        self.meshPipelineScreen = try makeMeshPSO(.screen)

        let maskDesc = MTLRenderPipelineDescriptor()
        maskDesc.vertexFunction = vsMesh
        maskDesc.fragmentFunction = fsMask
        maskDesc.colorAttachments[0].pixelFormat = .r8Unorm
        maskDesc.colorAttachments[0].isBlendingEnabled = true
        maskDesc.colorAttachments[0].rgbBlendOperation = .max
        maskDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        maskDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        self.maskPipeline = try dev.makeRenderPipelineState(descriptor: maskDesc)

        func makeEffectPSO(_ additive: Bool) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vsEffect
            desc.fragmentFunction = fsEffect
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try dev.makeRenderPipelineState(descriptor: desc)
        }
        self.effectPipelineAlpha = try makeEffectPSO(false)
        self.effectPipelineAdditive = try makeEffectPSO(true)

        let compDesc = MTLRenderPipelineDescriptor()
        compDesc.vertexFunction = vsFull
        compDesc.fragmentFunction = fsComp
        compDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.compositePipeline = try dev.makeRenderPipelineState(descriptor: compDesc)

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .linear
        sampDesc.magFilter = .linear
        sampDesc.sAddressMode = .clampToEdge
        sampDesc.tAddressMode = .clampToEdge
        self.sampler = dev.makeSamplerState(descriptor: sampDesc)!
    }

    public func uploadTextures(for avatar: SatLoadedAvatar) throws {
        textures.removeAll()
        for tex in avatar.model.textures {
            guard let bytes = avatar.textureData[tex.file] else {
                throw SatRenderError.textureDecodeFailed(tex.file)
            }
            textures[tex.file] = try decodeTextureWithEdgeBleed(bytes, name: tex.file)
        }
    }

    private func ensureOffscreenTargets(width: Int, height: Int) {
        let w = max(1, width)
        let h = max(1, height)
        if offscreenW == w && offscreenH == h && offscreenSceneTex != nil && maskTex != nil {
            return
        }
        offscreenW = w
        offscreenH = h
        let sceneDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false
        )
        sceneDesc.usage = [.renderTarget, .shaderRead]
        sceneDesc.storageMode = .private
        offscreenSceneTex = device.makeTexture(descriptor: sceneDesc)

        let maskDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false
        )
        maskDesc.usage = [.renderTarget, .shaderRead]
        maskDesc.storageMode = .private
        maskTex = device.makeTexture(descriptor: maskDesc)
    }

    public func encodeFrame(
        into commandBuffer: MTLCommandBuffer,
        targetTexture: MTLTexture,
        viewportWidth: Int,
        viewportHeight: Int,
        canvasSize: SatCanvas,
        camera: SatCameraTransform,
        drawables: [EvaluatedDrawable],
        effects: [EffectsRenderGroup],
        background: SatBackgroundMode,
        customColor: SIMD3<Float> = SIMD3<Float>(0.08, 0.07, 0.11)
    ) {
        ensureOffscreenTargets(width: viewportWidth, height: viewportHeight)
        guard let sceneTex = offscreenSceneTex, let mTex = maskTex else { return }

        let vw = Float(max(1, viewportWidth))
        let vh = Float(max(1, viewportHeight))
        let cw = Float(max(1.0, canvasSize.width))
        let ch = Float(max(1.0, canvasSize.height))
        let fitScale = min(vw / cw, vh / ch) * camera.zoom
        let drawW = cw * fitScale
        let drawH = ch * fitScale
        let oxPx = (vw - drawW) * 0.5 + camera.panX
        let oyPx = (vh - drawH) * 0.5 + camera.panY

        let sx = (2.0 * fitScale) / vw
        let sy = -(2.0 * fitScale) / vh
        let ndcOx = (2.0 * oxPx) / vw - 1.0
        let ndcOy = 1.0 - (2.0 * oyPx) / vh
        let baseToNDC = SIMD4<Float>(sx, sy, ndcOx, ndcOy)

        // Clear offscreen scene texture to transparent (0,0,0,0) before rendering
        let clearRP = MTLRenderPassDescriptor()
        clearRP.colorAttachments[0].texture = sceneTex
        clearRP.colorAttachments[0].loadAction = .clear
        clearRP.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        clearRP.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: clearRP) {
            drawEffects(effects.filter { $0.placement == .behind_avatar }, enc: enc, toNDC: baseToNDC, background: background)
            enc.endEncoding()
        }

        // Group draws seamlessly, switching render passes only when a clipMask changes
        var byMeshId: [String: EvaluatedDrawable] = [:]
        for d in drawables { byMeshId[d.meshId] = d }

        var activeMaskKey: [String]? = nil
        var activeEncoder: MTLRenderCommandEncoder? = nil

        func beginSceneEncoder() -> MTLRenderCommandEncoder? {
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = sceneTex
            rp.colorAttachments[0].loadAction = .load
            rp.colorAttachments[0].storeAction = .store
            return commandBuffer.makeRenderCommandEncoder(descriptor: rp)
        }

        var passedAboveCloak = false
        for dr in drawables {
            if !passedAboveCloak && dr.drawOrder >= 250 {
                passedAboveCloak = true
                let above = effects.filter { $0.placement == .above_cloak }
                if !above.isEmpty {
                    if activeEncoder == nil { activeEncoder = beginSceneEncoder() }
                    if let enc = activeEncoder {
                        drawEffects(above, enc: enc, toNDC: baseToNDC, background: background)
                    }
                }
            }

            if dr.opacity <= 0.001 || dr.indices.isEmpty { continue }
            guard let tex = textures[dr.textureFile] else { continue }

            let needsMask = !dr.clipMasks.isEmpty
            if needsMask && activeMaskKey != dr.clipMasks {
                activeEncoder?.endEncoding()
                activeEncoder = nil
                activeMaskKey = dr.clipMasks

                let maskRP = MTLRenderPassDescriptor()
                maskRP.colorAttachments[0].texture = mTex
                maskRP.colorAttachments[0].loadAction = .clear
                maskRP.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                maskRP.colorAttachments[0].storeAction = .store
                if let mEnc = commandBuffer.makeRenderCommandEncoder(descriptor: maskRP) {
                    mEnc.setRenderPipelineState(maskPipeline)
                    mEnc.setFragmentSamplerState(sampler, index: 0)
                    var u = GpuUniforms(toNDC: baseToNDC, params: .zero)
                    mEnc.setVertexBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
                    for mid in dr.clipMasks {
                        if let mDr = byMeshId[mid], let mGfxTex = textures[mDr.textureFile], !mDr.indices.isEmpty {
                            submitDrawableGeometry(mDr, opacityOverride: 1.0, enc: mEnc, tex: mGfxTex, maskTex: mTex)
                        }
                    }
                    mEnc.endEncoding()
                }
            }

            if activeEncoder == nil {
                activeEncoder = beginSceneEncoder()
            }
            guard let enc = activeEncoder else { continue }

            let pso: MTLRenderPipelineState
            switch dr.blendMode {
            case .normal: pso = meshPipelineNormal
            case .additive: pso = meshPipelineAdditive
            case .multiply: pso = meshPipelineMultiply
            case .screen: pso = meshPipelineScreen
            }
            enc.setRenderPipelineState(pso)
            var u = GpuUniforms(
                toNDC: baseToNDC,
                params: SIMD4<Float>(needsMask ? 1.0 : 0.0, dr.invertedMask ? 1.0 : 0.0, 0.0, 0.0)
            )
            enc.setVertexBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
            enc.setFragmentSamplerState(sampler, index: 0)
            submitDrawableGeometry(dr, opacityOverride: dr.opacity, enc: enc, tex: tex, maskTex: mTex)
        }

        let fg = effects.filter { $0.placement == .foreground }
        if !fg.isEmpty {
            if activeEncoder == nil { activeEncoder = beginSceneEncoder() }
            if let enc = activeEncoder {
                drawEffects(fg, enc: enc, toNDC: baseToNDC, background: background)
            }
        }
        activeEncoder?.endEncoding()

        // Final composite pass over chosen background
        let compRP = MTLRenderPassDescriptor()
        compRP.colorAttachments[0].texture = targetTexture
        compRP.colorAttachments[0].loadAction = .clear
        compRP.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        compRP.colorAttachments[0].storeAction = .store
        if let compEnc = commandBuffer.makeRenderCommandEncoder(descriptor: compRP) {
            compEnc.setRenderPipelineState(compositePipeline)
            let modeCode: Float = {
                switch background {
                case .black: return 0
                case .greenScreen: return 1
                case .white: return 2
                case .checkerboard: return 3
                case .transparent: return 4
                case .custom: return 5
                }
            }()
            var u = GpuUniforms(
                toNDC: SIMD4<Float>(vw, vh, customColor.x, customColor.y),
                params: SIMD4<Float>(modeCode, customColor.z, 0, 0)
            )
            compEnc.setVertexBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
            compEnc.setFragmentBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
            compEnc.setFragmentTexture(sceneTex, index: 0)
            compEnc.setFragmentSamplerState(sampler, index: 0)
            compEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            compEnc.endEncoding()
        }
    }

    private func submitDrawableGeometry(
        _ dr: EvaluatedDrawable,
        opacityOverride: Float,
        enc: MTLRenderCommandEncoder,
        tex: MTLTexture,
        maskTex: MTLTexture
    ) {
        let count = dr.positions.count / 2
        guard count >= 3 else { return }
        var verts: [GpuMeshVertex] = []
        verts.reserveCapacity(count)
        let clip = SIMD4<Float>(dr.uvClipRect[0], dr.uvClipRect[1], dr.uvClipRect[2], dr.uvClipRect[3])
        let col = SIMD4<Float>(1, 1, 1, opacityOverride)
        for i in 0..<count {
            verts.append(GpuMeshVertex(
                pos: SIMD2<Float>(dr.positions[i * 2], dr.positions[i * 2 + 1]),
                uv: SIMD2<Float>(dr.uvs[i * 2], dr.uvs[i * 2 + 1]),
                uvClip: clip,
                color: col
            ))
        }
        guard let vBuf = device.makeBuffer(bytes: &verts, length: verts.count * MemoryLayout<GpuMeshVertex>.stride, options: .storageModeShared),
              let iBuf = device.makeBuffer(bytes: dr.indices, length: dr.indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
            return
        }
        enc.setVertexBuffer(vBuf, offset: 0, index: 0)
        enc.setFragmentTexture(tex, index: 0)
        enc.setFragmentTexture(maskTex, index: 1)
        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: dr.indices.count,
            indexType: .uint32,
            indexBuffer: iBuf,
            indexBufferOffset: 0
        )
    }

    private func drawEffects(
        _ groups: [EffectsRenderGroup],
        enc: MTLRenderCommandEncoder,
        toNDC: SIMD4<Float>,
        background: SatBackgroundMode
    ) {
        for g in groups where !g.indices.isEmpty {
            let useAdd = (g.blendMode == .additive || g.blendMode == .screen) && !(g.chromaSafe && background == .greenScreen)
            enc.setRenderPipelineState(useAdd ? effectPipelineAdditive : effectPipelineAlpha)
            var u = GpuUniforms(toNDC: toNDC, params: .zero)
            enc.setVertexBytes(&u, length: MemoryLayout<GpuUniforms>.stride, index: 1)
            var verts = g.vertices.map {
                GpuEffectVertex(pos: SIMD2<Float>($0.x, $0.y), uv: SIMD2<Float>($0.u, $0.v), color: SIMD4<Float>($0.r, $0.g, $0.b, $0.a))
            }
            guard let vBuf = device.makeBuffer(bytes: &verts, length: verts.count * MemoryLayout<GpuEffectVertex>.stride, options: .storageModeShared),
                  let iBuf = device.makeBuffer(bytes: g.indices, length: g.indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
                continue
            }
            enc.setVertexBuffer(vBuf, offset: 0, index: 0)
            enc.drawIndexedPrimitives(
                type: .triangle,
                indexCount: g.indices.count,
                indexType: .uint32,
                indexBuffer: iBuf,
                indexBufferOffset: 0
            )
        }
    }

    public func renderOffscreenToPNG(
        avatar: SatLoadedAvatar,
        drawables: [EvaluatedDrawable],
        effects: [EffectsRenderGroup],
        width: Int,
        height: Int,
        camera: SatCameraTransform = SatCameraTransform(),
        background: SatBackgroundMode = .black,
        outputURL: URL
    ) throws {
        try uploadTextures(for: avatar)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc),
              let cmd = commandQueue.makeCommandBuffer() else {
            throw SatRenderError.readbackFailed("Unable to allocate offscreen Metal render target.")
        }
        encodeFrame(
            into: cmd,
            targetTexture: target,
            viewportWidth: width,
            viewportHeight: height,
            canvasSize: avatar.manifest.canvas,
            camera: camera,
            drawables: drawables,
            effects: effects,
            background: background
        )
        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error {
            throw SatRenderError.readbackFailed(err.localizedDescription)
        }

        let bpr = width * 4
        var bgra = [UInt8](repeating: 0, count: bpr * height)
        target.getBytes(&bgra, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        // Convert BGRA -> RGBA for PNG output
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]
            rgba[i + 1] = bgra[i + 1]
            rgba[i + 2] = bgra[i]
            rgba[i + 3] = bgra[i + 3]
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bpr, space: cs, bitmapInfo: bitmapInfo,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ),
              let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
            throw SatRenderError.readbackFailed("Failed to encode output PNG.")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        if !CGImageDestinationFinalize(dest) {
            throw SatRenderError.readbackFailed("CGImageDestinationFinalize failed writing '\(outputURL.path)'.")
        }
    }

    /// Zero-copy Metal render directly into an IOSurface-backed BGRA CVPixelBuffer for real-time virtual webcam streaming.
    public func renderFrame(
        into pixelBuffer: CVPixelBuffer,
        canvasSize: SatCanvas,
        camera: SatCameraTransform,
        drawables: [EvaluatedDrawable],
        effects: [EffectsRenderGroup],
        background: SatBackgroundMode,
        customColor: SIMD3<Float> = SIMD3<Float>(0.08, 0.07, 0.11)
    ) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let ioSurfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            throw SatRenderError.readbackFailed("CVPixelBuffer lacks IOSurface backing.")
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: desc, iosurface: ioSurfaceRef, plane: 0),
              let cmd = commandQueue.makeCommandBuffer() else {
            throw SatRenderError.readbackFailed("Unable to bind IOSurface Metal texture.")
        }
        encodeFrame(
            into: cmd,
            targetTexture: target,
            viewportWidth: width,
            viewportHeight: height,
            canvasSize: canvasSize,
            camera: camera,
            drawables: drawables,
            effects: effects,
            background: background,
            customColor: customColor
        )
        cmd.commit()
        cmd.waitUntilCompleted()
        if let err = cmd.error {
            throw SatRenderError.readbackFailed(err.localizedDescription)
        }
    }

    private func decodeTextureWithEdgeBleed(_ data: Data, name: String) throws -> MTLTexture {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw SatRenderError.textureDecodeFailed(name)
        }
        let w = cg.width
        let h = cg.height
        let bpr = w * 4
        var rgba = [UInt8](repeating: 0, count: bpr * h)

        // Read direct unpremultiplied data if PNG is strictly 32bpp 8bpc packed RGBA8; otherwise draw via CGContext & unpremultiply cleanly
        let cs = CGColorSpaceCreateDeviceRGB()
        let byteOrder = cg.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        if cg.bitsPerComponent == 8 && cg.bitsPerPixel == 32 && cg.bytesPerRow == bpr &&
            cg.alphaInfo == .last && (byteOrder == 0 || byteOrder == CGImageByteOrderInfo.order32Big.rawValue),
           let dp = cg.dataProvider, let raw = dp.data, CFDataGetLength(raw) >= bpr * h {
            CFDataGetBytes(raw, CFRangeMake(0, bpr * h), &rgba)
        } else {
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: info.rawValue) else {
                throw SatRenderError.textureDecodeFailed(name)
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            for i in stride(from: 0, to: rgba.count, by: 4) {
                let a = Int(rgba[i + 3])
                if a > 0 && a < 255 {
                    rgba[i] = UInt8(min(255, (Int(rgba[i]) * 255 + a / 2) / a))
                    rgba[i + 1] = UInt8(min(255, (Int(rgba[i + 1]) * 255 + a / 2) / a))
                    rgba[i + 2] = UInt8(min(255, (Int(rgba[i + 2]) * 255 + a / 2) / a))
                }
            }
        }

        // BFS color bleed for 6 rings into transparent alpha==0 pixels to prevent bilinear halo fringes
        Self.bleedStraightRGBA(&rgba, width: w, height: h, rings: 6)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw SatRenderError.textureDecodeFailed(name)
        }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: rgba, bytesPerRow: bpr)
        return tex
    }

    public static func bleedStraightRGBA(_ rgba: inout [UInt8], width w: Int, height h: Int, rings: Int = 6) {
        let n = w * h
        var filled = [Bool](repeating: false, count: n)
        var ring: [Int] = []
        ring.reserveCapacity(n / 8)

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if rgba[i * 4 + 3] > 0 {
                    filled[i] = true
                }
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if !filled[i] { continue }
                if (x > 0 && !filled[i - 1]) || (x + 1 < w && !filled[i + 1]) ||
                   (y > 0 && !filled[i - w]) || (y + 1 < h && !filled[i + w]) {
                    ring.append(i)
                }
            }
        }

        for _ in 0..<rings {
            if ring.isEmpty { break }
            var next: [Int] = []
            for i in ring {
                let x = i % w
                let y = i / w
                let base = i * 4
                let r = rgba[base], g = rgba[base + 1], b = rgba[base + 2]
                let neighbors = [
                    x > 0 ? i - 1 : -1,
                    x + 1 < w ? i + 1 : -1,
                    y > 0 ? i - w : -1,
                    y + 1 < h ? i + w : -1
                ]
                for nb in neighbors where nb >= 0 && !filled[nb] {
                    filled[nb] = true
                    let dst = nb * 4
                    rgba[dst] = r
                    rgba[dst + 1] = g
                    rgba[dst + 2] = b
                    rgba[dst + 3] = 0
                    next.append(nb)
                }
            }
            ring = next
        }
    }
}
