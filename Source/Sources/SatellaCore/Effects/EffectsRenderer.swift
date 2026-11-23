import Foundation

public struct EffectQuadVertex: Sendable {
    public var x: Float
    public var y: Float
    public var u: Float
    public var v: Float
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float
}

public struct EffectsRenderGroup: Sendable {
    public var placement: SatEffectPlacement
    public var blendMode: SatEffectBlend
    public var chromaSafe: Bool
    public var textureFile: String?
    public var kind: SatEffectKind
    public var vertices: [EffectQuadVertex]
    public var indices: [UInt32]
}

public final class EffectsRenderer {
    private struct Particle {
        var x: Double
        var y: Double
        var age: Double
        var life: Double
        var size: Double
        var phase: Double
        var seed: Double
        var regionIdx: Int
    }

    private struct LayerRuntime {
        var spec: SatEffectLayer
        var particles: [Particle]
        var time: Double = 0.0
    }

    private var layers: [LayerRuntime] = []
    public var qualityScale: Double = 1.0

    public init() {}

    public func load(specs: [SatEffectsSpec]) {
        layers = []
        var seedCounter: UInt64 = 0x5A7E_11A0_0001
        func nextRand() -> Double {
            seedCounter = seedCounter &* 6364136223846793005 &+ 1442695040888963407
            return Double((seedCounter >> 11) & 0x1FFFFF) / Double(0x200000)
        }

        for fx in specs {
            for layer in fx.layers {
                guard !layer.regions.isEmpty else { continue }
                let minLife = max(0.4, layer.lifeRange?.first ?? 2.8)
                let maxLife = max(minLife, layer.lifeRange?.last ?? 5.5)
                let minSize = max(4.0, layer.sizeRange?.first ?? 45.0)
                let maxSize = max(minSize, layer.sizeRange?.last ?? 130.0)
                let totalWeight = layer.regions.reduce(0.0) { $0 + ($1.weight ?? 1.0) }

                var list: [Particle] = []
                list.reserveCapacity(layer.particleCount)
                for _ in 0..<layer.particleCount {
                    var pick = nextRand() * max(1e-4, totalWeight)
                    var rIdx = 0
                    for (ri, reg) in layer.regions.enumerated() {
                        pick -= (reg.weight ?? 1.0)
                        if pick <= 0 {
                            rIdx = ri
                            break
                        }
                    }
                    let reg = layer.regions[rIdx]
                    let life = minLife + nextRand() * (maxLife - minLife)
                    list.append(Particle(
                        x: reg.x + nextRand() * reg.width,
                        y: reg.y + nextRand() * reg.height,
                        age: nextRand() * life,
                        life: life,
                        size: minSize + nextRand() * (maxSize - minSize),
                        phase: nextRand() * Double.pi * 2.0,
                        seed: nextRand(),
                        regionIdx: rIdx
                    ))
                }
                layers.append(LayerRuntime(spec: layer, particles: list))
            }
        }
    }

    public func step(
        dt: Double,
        paramValues: [String: Double],
        deformerStates: [String: EvaluatedDeformerState]
    ) -> [EffectsRenderGroup] {
        var groups: [EffectsRenderGroup] = []
        let q = max(0.25, min(1.0, qualityScale))

        for li in 0..<layers.count {
            layers[li].time += dt
            let spec = layers[li].spec
            let intensity = spec.intensityParam.flatMap { paramValues[$0] } ?? 1.0
            let layerAlpha = max(0.0, min(1.0, (spec.opacity ?? 0.65) * intensity))
            if layerAlpha <= 0.005 { continue }

            let rise = spec.riseSpeed ?? 18.0
            let drift = spec.driftX ?? 0.0
            let swirlF = spec.swirlFrequency ?? 1.1
            let swirlA = spec.swirlAmplitude ?? 14.0
            let turb = spec.turbulence ?? 10.0

            let followState = spec.followDeformer.flatMap { deformerStates[$0] }
            let countLimit = max(1, Int(Double(layers[li].particles.count) * q))

            var verts: [EffectQuadVertex] = []
            var inds: [UInt32] = []
            verts.reserveCapacity(countLimit * 4)
            inds.reserveCapacity(countLimit * 6)

            for pi in 0..<layers[li].particles.count {
                var p = layers[li].particles[pi]
                p.age += dt
                if p.age >= p.life {
                    p.age = p.age.truncatingRemainder(dividingBy: p.life)
                    let reg = spec.regions[p.regionIdx]
                    p.x = reg.x + p.seed * reg.width
                    p.y = reg.y + ((p.seed * 17.31).truncatingRemainder(dividingBy: 1.0)) * reg.height
                }
                let t = p.age / p.life
                let fade = sin(t * Double.pi) // Smooth 0 -> 1 -> 0 envelope
                let swirlX = sin(layers[li].time * swirlF + p.phase) * swirlA
                    + cos(layers[li].time * 0.73 + p.seed * 9.0) * turb * 0.5
                let px = p.x + drift * p.age + swirlX
                let py = p.y - rise * p.age

                layers[li].particles[pi] = p
                if pi >= countLimit { continue }

                let (wx, wy): (Double, Double)
                if let fs = followState {
                    (wx, wy) = MeshDeformer.transformPoint(x: px, y: py, through: fs)
                } else {
                    (wx, wy) = (px, py)
                }

                // Attenuate cleanly inside face / chest exclusion boxes
                var exMask = 1.0
                for box in spec.exclusionBoxes ?? [] {
                    let cx = box.x + box.width * 0.5
                    let cy = box.y + box.height * 0.5
                    let nx = abs(wx - cx) / max(1.0, box.width * 0.5)
                    let ny = abs(wy - cy) / max(1.0, box.height * 0.5)
                    let dist = max(nx, ny)
                    if dist < 1.25 {
                        let keep = max(0.0, min(1.0, (dist - 0.75) / 0.5))
                        exMask *= keep
                    }
                }
                if exMask <= 0.01 { continue }

                let color = sampleColor(spec.colors, at: t)
                let a = Float(color.a * fade * layerAlpha * exMask)
                if a <= 0.002 { continue }

                let scaleFactor = (spec.kind == .miasma) ? (0.85 + 0.45 * t) : (0.7 + 0.5 * sin(t * Double.pi))
                let half = Float(p.size * 0.5 * scaleFactor)
                let base = UInt32(verts.count)
                let xf = Float(wx)
                let yf = Float(wy)
                verts.append(EffectQuadVertex(x: xf - half, y: yf - half, u: 0, v: 0, r: Float(color.r), g: Float(color.g), b: Float(color.b), a: a))
                verts.append(EffectQuadVertex(x: xf + half, y: yf - half, u: 1, v: 0, r: Float(color.r), g: Float(color.g), b: Float(color.b), a: a))
                verts.append(EffectQuadVertex(x: xf + half, y: yf + half, u: 1, v: 1, r: Float(color.r), g: Float(color.g), b: Float(color.b), a: a))
                verts.append(EffectQuadVertex(x: xf - half, y: yf + half, u: 0, v: 1, r: Float(color.r), g: Float(color.g), b: Float(color.b), a: a))
                inds.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }

            if !inds.isEmpty {
                groups.append(EffectsRenderGroup(
                    placement: spec.placement,
                    blendMode: spec.blendMode ?? .alpha,
                    chromaSafe: spec.chromaSafe ?? true,
                    textureFile: spec.texture,
                    kind: spec.kind,
                    vertices: verts,
                    indices: inds
                ))
            }
        }
        return groups
    }

    private func sampleColor(_ stops: [[Double]], at t: Double) -> (r: Double, g: Double, b: Double, a: Double) {
        guard !stops.isEmpty else { return (0.5, 0.2, 0.8, 0.5) }
        if stops.count == 1 || t <= 0 {
            let s = stops[0]
            return (s[0], s[1], s[2], s[3])
        }
        if t >= 1 {
            let s = stops[stops.count - 1]
            return (s[0], s[1], s[2], s[3])
        }
        let scaled = t * Double(stops.count - 1)
        let i0 = Int(floor(scaled))
        let i1 = min(stops.count - 1, i0 + 1)
        let f = scaled - Double(i0)
        let a = stops[i0], b = stops[i1]
        return (
            a[0] + (b[0] - a[0]) * f,
            a[1] + (b[1] - a[1]) * f,
            a[2] + (b[2] - a[2]) * f,
            a[3] + (b[3] - a[3]) * f
        )
    }
}
