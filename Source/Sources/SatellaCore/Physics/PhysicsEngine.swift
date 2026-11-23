import Foundation

public enum BreastPhysicsLevel: String, Codable, CaseIterable, Sendable {
    case off = "Off"
    case subtle = "Subtle"
    case normal = "Normal"
    case strong = "Strong"

    public var multiplier: Double {
        switch self {
        case .off: return 0.0
        case .subtle: return 0.45
        case .normal: return 1.0
        case .strong: return 1.65
        }
    }
}

public final class PhysicsEngine {
    private struct NodeState {
        var x: Double = 0
        var y: Double = 0
        var vx: Double = 0
        var vy: Double = 0
    }

    private struct GroupRuntime {
        var spec: SatPhysicsGroupSpec
        var stiffness: Double
        var damping: Double
        var inertia: Double
        var gravityScale: Double
        var windWeight: Double
        var maxOutput: Double
        var nodes: [NodeState]
        var posX: Double = 0
        var posY: Double = 0
        var velX: Double = 0
        var velY: Double = 0
        var lastInputX: Double = 0
        var lastInputY: Double = 0
        var lastVelX: Double = 0
        var lastVelY: Double = 0
        var smoothAccX: Double = 0
        var smoothAccY: Double = 0
        var initialized: Bool = false
    }

    private var spec: SatPhysicsSpec?
    private var groups: [GroupRuntime] = []
    private var accumulator: Double = 0.0
    public var enabled: Bool = true
    public var globalIntensity: Double = 1.0
    public var breastPhysicsLevel: BreastPhysicsLevel = .normal
    public var categoryMultipliers: [SatPhysicsCategory: Double] = [:]
    public var disabledGroups: Set<String> = []
    public var windOverride: (Double, Double)? = nil

    public var availableCategories: [SatPhysicsCategory] {
        var seen = Set<SatPhysicsCategory>()
        var ordered: [SatPhysicsCategory] = []
        for g in groups {
            let cat = g.spec.category ?? .custom
            if seen.insert(cat).inserted { ordered.append(cat) }
        }
        return ordered
    }

    public func multiplier(for group: SatPhysicsGroupSpec) -> Double {
        if disabledGroups.contains(group.id) { return 0.0 }
        let cat = group.category ?? .custom
        if cat == .breast {
            return breastPhysicsLevel.multiplier * (categoryMultipliers[.breast] ?? 1.0)
        }
        return globalIntensity * (categoryMultipliers[cat] ?? 1.0)
    }

    public init(spec: SatPhysicsSpec?) {
        self.spec = spec
        rebuild()
    }

    public func load(spec: SatPhysicsSpec?) {
        self.spec = spec
        self.accumulator = 0.0
        rebuild()
    }

    public func reset() {
        accumulator = 0.0
        for i in 0..<groups.count {
            groups[i].posX = 0
            groups[i].posY = 0
            groups[i].velX = 0
            groups[i].velY = 0
            groups[i].smoothAccX = 0
            groups[i].smoothAccY = 0
            groups[i].initialized = false
            for ni in 0..<groups[i].nodes.count {
                let cumLen = groups[i].spec.nodes?[0...ni].reduce(0.0) { $0 + $1.length } ?? Double(ni) * 10.0
                groups[i].nodes[ni] = NodeState(x: 0, y: cumLen, vx: 0, vy: 0)
            }
        }
    }

    private func rebuild() {
        guard let spec = spec else {
            groups = []
            return
        }
        groups = spec.groups.map { g in
            let presetDefaults: (stiff: Double, damp: Double, inert: Double, grav: Double) = {
                switch g.preset ?? .custom {
                case .light_hair: return (38.0, 5.8, 1.15, 1.0)
                case .heavy_fabric: return (16.0, 4.2, 0.85, 1.35)
                case .soft_body: return (46.0, 8.2, 0.65, 0.9)
                case .accessory: return (52.0, 6.0, 1.0, 1.0)
                case .custom: return (32.0, 5.5, 1.0, 1.0)
                }
            }()
            var nodeStates: [NodeState] = []
            if let ns = g.nodes {
                var cum = 0.0
                for (i, n) in ns.enumerated() {
                    if i > 0 { cum += n.length }
                    nodeStates.append(NodeState(x: 0, y: cum, vx: 0, vy: 0))
                }
            }
            return GroupRuntime(
                spec: g,
                stiffness: g.stiffness ?? presetDefaults.stiff,
                damping: g.damping ?? presetDefaults.damp,
                inertia: g.inertia ?? presetDefaults.inert,
                gravityScale: g.gravityScale ?? presetDefaults.grav,
                windWeight: g.windWeight ?? 1.0,
                maxOutput: g.maxOutput ?? 1.0,
                nodes: nodeStates
            )
        }
    }

    public func step(
        dt rawDt: Double,
        parameters: [SatParameterSpec],
        values: inout [String: Double]
    ) {
        guard enabled, let spec = spec, !groups.isEmpty else { return }
        let dt = max(0.0, min(0.1, rawDt))
        let fixedStep = max(1e-4, min(0.05, spec.fixedTimestep))
        accumulator += dt

        let paramMeta: [String: SatParameterSpec] = Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0) })
        let baseGrav = spec.gravity ?? [0.0, 1.0]
        let gx = baseGrav.count >= 2 ? baseGrav[0] : 0.0
        let gy = baseGrav.count >= 2 ? baseGrav[1] : 1.0
        let baseWind = windOverride ?? (
            (spec.wind?.count ?? 0) >= 2 ? (spec.wind![0], spec.wind![1]) : (0.0, 0.0)
        )

        var substeps = 0
        while accumulator >= fixedStep && substeps < 8 {
            accumulator -= fixedStep
            substeps += 1

            for gi in 0..<groups.count {
                let catMult = multiplier(for: groups[gi].spec)
                if catMult <= 1e-6 {
                    groups[gi].posX = 0
                    groups[gi].posY = 0
                    groups[gi].velX = 0
                    groups[gi].velY = 0
                    continue
                }

                // Sample normalized inputs
                var inX = 0.0
                var inY = 0.0
                var inAngle = 0.0
                for inp in groups[gi].spec.inputs {
                    guard let meta = paramMeta[inp.parameter] else { continue }
                    let rawVal = values[inp.parameter] ?? meta.default
                    let span = max(1e-6, (meta.max - meta.min) * 0.5)
                    let mid = (meta.min + meta.max) * 0.5
                    let norm = (rawVal - mid) / span
                    let signed = norm * (inp.reflect == true ? -1.0 : 1.0) * inp.weight
                    switch inp.kind {
                    case .x: inX += signed
                    case .y: inY += signed
                    case .angle: inAngle += signed
                    }
                }

                if !groups[gi].initialized {
                    groups[gi].lastInputX = inX
                    groups[gi].lastInputY = inY
                    groups[gi].lastVelX = 0
                    groups[gi].lastVelY = 0
                    groups[gi].smoothAccX = 0
                    groups[gi].smoothAccY = 0
                    groups[gi].initialized = true
                }

                let rawVx = (inX - groups[gi].lastInputX) / fixedStep
                let rawVy = (inY - groups[gi].lastInputY) / fixedStep
                // Smooth derivative pipeline prevents camera frame-rate jitter from causing micro-twitches
                let velAlpha = 1.0 - exp(-fixedStep * 22.0)
                let vx = groups[gi].lastVelX + (rawVx - groups[gi].lastVelX) * velAlpha
                let vy = groups[gi].lastVelY + (rawVy - groups[gi].lastVelY) * velAlpha

                let rawAx = max(-18.0, min(18.0, (vx - groups[gi].lastVelX) / fixedStep))
                let rawAy = max(-18.0, min(18.0, (vy - groups[gi].lastVelY) / fixedStep))
                let accAlpha = 1.0 - exp(-fixedStep * 18.0)
                let ax = groups[gi].smoothAccX + (rawAx - groups[gi].smoothAccX) * accAlpha
                let ay = groups[gi].smoothAccY + (rawAy - groups[gi].smoothAccY) * accAlpha

                groups[gi].lastInputX = inX
                groups[gi].lastInputY = inY
                groups[gi].lastVelX = vx
                groups[gi].lastVelY = vy
                groups[gi].smoothAccX = ax
                groups[gi].smoothAccY = ay

                switch groups[gi].spec.type {
                case .spring2d:
                    let k = groups[gi].stiffness
                    let c = groups[gi].damping
                    let inert = groups[gi].inertia
                    let driveX = max(-28.0, min(28.0, ax + 2.4 * vx))
                    let driveY = max(-28.0, min(28.0, ay + 2.4 * vy))
                    let fx = -inert * driveX - k * groups[gi].posX - c * groups[gi].velX + baseWind.0 * groups[gi].windWeight * 0.05
                    let fy = -inert * driveY - k * groups[gi].posY - c * groups[gi].velY + (gx * 0.0 + baseWind.1) * groups[gi].windWeight * 0.05
                    groups[gi].velX += fx * fixedStep
                    groups[gi].velY += fy * fixedStep
                    groups[gi].posX += groups[gi].velX * fixedStep
                    groups[gi].posY += groups[gi].velY * fixedStep

                    let maxExc = 1.5
                    groups[gi].posX = max(-maxExc, min(maxExc, groups[gi].posX))
                    groups[gi].posY = max(-maxExc, min(maxExc, groups[gi].posY))
                    if abs(groups[gi].posX) < 1e-5 && abs(groups[gi].velX) < 1e-5 { groups[gi].posX = 0; groups[gi].velX = 0 }
                    if abs(groups[gi].posY) < 1e-5 && abs(groups[gi].velY) < 1e-5 { groups[gi].posY = 0; groups[gi].velY = 0 }

                case .pendulum:
                    let nodeSpecs = groups[gi].spec.nodes ?? []
                    guard nodeSpecs.count >= 2 else { continue }
                    // Anchor moves subtly with inputs
                    groups[gi].nodes[0].x = inX * 2.0
                    groups[gi].nodes[0].y = inY * 2.0
                    let tiltRad = inAngle * 0.35
                    let targetDirX = gx - sin(tiltRad)
                    let targetDirY = gy * cos(tiltRad)

                    for ni in 1..<nodeSpecs.count {
                        let nSpec = nodeSpecs[ni]
                        let parent = groups[gi].nodes[ni - 1]
                        var node = groups[gi].nodes[ni]
                        let targetX = parent.x + targetDirX * nSpec.length
                        let targetY = parent.y + targetDirY * nSpec.length

                        let springK = (nSpec.stiffness > 0 ? nSpec.stiffness : groups[gi].stiffness) * groups[gi].gravityScale
                        let damp = nSpec.damping >= 0 ? nSpec.damping : groups[gi].damping
                        let fx = (targetX - node.x) * springK + baseWind.0 * groups[gi].windWeight - node.vx * damp - ax * groups[gi].inertia * 0.35
                        let fy = (targetY - node.y) * springK + baseWind.1 * groups[gi].windWeight - node.vy * damp - ay * groups[gi].inertia * 0.2

                        node.vx += (fx / max(0.1, nSpec.mass)) * fixedStep
                        node.vy += (fy / max(0.1, nSpec.mass)) * fixedStep
                        var nx = node.x + node.vx * fixedStep
                        var ny = node.y + node.vy * fixedStep

                        // Length constraint
                        let dx = nx - parent.x
                        let dy = ny - parent.y
                        let len = hypot(dx, dy)
                        if len > 1e-6 {
                            nx = parent.x + (dx / len) * nSpec.length
                            ny = parent.y + (dy / len) * nSpec.length
                        }
                        node.x = nx
                        node.y = ny
                        groups[gi].nodes[ni] = node
                    }
                }
            }
        }

        // Write simulated outputs into parameter values
        for g in groups {
            let catMult = multiplier(for: g.spec)
            for outp in g.spec.outputs {
                guard let meta = paramMeta[outp.parameter] else { continue }
                let rawOut: Double
                switch g.spec.type {
                case .spring2d:
                    switch outp.kind {
                    case .x: rawOut = g.posX
                    case .y, .angle: rawOut = g.posY
                    }
                case .pendulum:
                    let ni = max(1, min(g.nodes.count - 1, outp.nodeIndex ?? (g.nodes.count - 1)))
                    guard ni < g.nodes.count else { continue }
                    let n = g.nodes[ni]
                    let p = g.nodes[ni - 1]
                    let dx = n.x - p.x
                    let dy = n.y - p.y
                    switch outp.kind {
                    case .angle:
                        // Angle relative to vertical down (+Y)
                        rawOut = atan2(dx, max(1e-4, dy))
                    case .x:
                        rawOut = dx
                    case .y:
                        let restLen = g.spec.nodes?[ni].length ?? 10.0
                        rawOut = dy - restLen
                    }
                }

                let sign = outp.reflect == true ? -1.0 : 1.0
                let scaled = max(-g.maxOutput, min(g.maxOutput, rawOut * outp.scale * sign * catMult))
                let weight = max(0.0, min(1.0, outp.weight ?? 1.0))
                let cur = values[outp.parameter] ?? meta.default
                let blended = cur * (1.0 - weight) + (meta.default + scaled) * weight
                values[outp.parameter] = max(meta.min, min(meta.max, blended))
            }
        }
    }
}
