import Foundation

public struct EvaluatedVertex: Sendable {
    public var x: Float
    public var y: Float
    public var u: Float
    public var v: Float
}

public struct EvaluatedDrawable: Sendable {
    public var id: String
    public var meshId: String
    public var textureFile: String
    public var positions: [Float] // x0, y0, x1, y1 ...
    public var uvs: [Float]       // u0, v0, u1, v1 ...
    public var indices: [UInt32]
    public var drawOrder: Double
    public var opacity: Float
    public var blendMode: SatBlendMode
    public var clipMasks: [String]
    public var invertedMask: Bool
    public var uvClipRect: [Float] // [u0, v0, u1, v1]
    public var doubleSided: Bool
}

public struct EvaluatedDeformerState: Sendable {
    public var id: String
    public var type: SatDeformerType
    public var parent: String?
    public var pivotX: Double
    public var pivotY: Double
    public var angleDeg: Double
    public var translateX: Double
    public var translateY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var opacity: Double
    public var bounds: SatBounds?
    public var rows: Int
    public var cols: Int
    public var gridPoints: [Double] // deformed grid [x0,y0, x1,y1 ...] in canvas px
}

public enum MeshDeformer {
    /// Compute N-D Cartesian multilinear interpolation weights & flat keyform indices.
    public static func sampleAxes(
        axes: [SatAxisSpec],
        paramValues: [String: Double]
    ) -> [(index: Int, weight: Double)] {
        if axes.isEmpty {
            return [(0, 1.0)]
        }
        var current: [(index: Int, weight: Double)] = [(0, 1.0)]
        var stride = 1
        for axis in axes {
            let keys = axis.keys
            guard !keys.isEmpty else { continue }
            let val = paramValues[axis.parameter] ?? 0.0
            let brackets: [(Int, Double)]
            if keys.count == 1 || val <= keys[0] {
                brackets = [(0, 1.0)]
            } else if val >= keys[keys.count - 1] {
                brackets = [(keys.count - 1, 1.0)]
            } else {
                var hi = 1
                while hi < keys.count && keys[hi] < val {
                    hi += 1
                }
                let lo = hi - 1
                let span = keys[hi] - keys[lo]
                let t = span > 1e-9 ? (val - keys[lo]) / span : 0.0
                if t <= 1e-6 {
                    brackets = [(lo, 1.0)]
                } else if t >= 1.0 - 1e-6 {
                    brackets = [(hi, 1.0)]
                } else {
                    brackets = [(lo, 1.0 - t), (hi, t)]
                }
            }

            var next: [(index: Int, weight: Double)] = []
            next.reserveCapacity(current.count * brackets.count)
            for (baseIdx, baseW) in current {
                for (kIdx, kW) in brackets {
                    next.append((baseIdx + kIdx * stride, baseW * kW))
                }
            }
            current = next
            stride *= keys.count
        }
        return current
    }

    public static func evaluateDeformer(
        _ def: SatDeformerSpec,
        paramValues: [String: Double]
    ) -> EvaluatedDeformerState {
        let samples = sampleAxes(axes: def.axes ?? [], paramValues: paramValues)
        let keyforms = def.keyforms ?? []

        var angle = 0.0
        var tx = 0.0
        var ty = 0.0
        var sx = 0.0
        var sy = 0.0
        var sxWeightSum = 0.0
        var opacity = 0.0
        var opacWeightSum = 0.0

        let rows = def.rows ?? 1
        let cols = def.cols ?? 1
        let gridCount = (rows + 1) * (cols + 1)
        var gridOffsets = [Double](repeating: 0.0, count: def.type == .warp ? gridCount * 2 : 0)

        for (idx, w) in samples {
            guard idx < keyforms.count else {
                // Default identity fallback for missing keyform
                sx += 1.0 * w
                sy += 1.0 * w
                sxWeightSum += w
                opacity += 1.0 * w
                opacWeightSum += w
                continue
            }
            let kf = keyforms[idx]
            angle += (kf.angleDeg ?? 0.0) * w
            if let tr = kf.translate, tr.count >= 2 {
                tx += tr[0] * w
                ty += tr[1] * w
            }
            if let sc = kf.scale, sc.count >= 2 {
                sx += sc[0] * w
                sy += sc[1] * w
            } else {
                sx += 1.0 * w
                sy += 1.0 * w
            }
            sxWeightSum += w
            opacity += (kf.opacity ?? 1.0) * w
            opacWeightSum += w

            if def.type == .warp, let offs = kf.gridOffsets, offs.count == gridCount {
                for i in 0..<gridCount {
                    gridOffsets[i * 2] += offs[i][0] * w
                    gridOffsets[i * 2 + 1] += offs[i][1] * w
                }
            }
        }

        if sxWeightSum == 0.0 {
            sx = 1.0
            sy = 1.0
        }
        if opacWeightSum == 0.0 {
            opacity = 1.0
        }

        var gridPoints: [Double] = []
        if def.type == .warp, let b = def.bounds {
            gridPoints.reserveCapacity(gridCount * 2)
            for r in 0...rows {
                let fy = Double(r) / Double(rows)
                for c in 0...cols {
                    let fx = Double(c) / Double(cols)
                    let i = r * (cols + 1) + c
                    let rx = b.x + b.width * fx
                    let ry = b.y + b.height * fy
                    gridPoints.append(rx + gridOffsets[i * 2])
                    gridPoints.append(ry + gridOffsets[i * 2 + 1])
                }
            }
        }

        return EvaluatedDeformerState(
            id: def.id,
            type: def.type,
            parent: def.parent,
            pivotX: (def.pivot?.count ?? 0) >= 2 ? def.pivot![0] : 0.0,
            pivotY: (def.pivot?.count ?? 0) >= 2 ? def.pivot![1] : 0.0,
            angleDeg: angle,
            translateX: tx,
            translateY: ty,
            scaleX: sx,
            scaleY: sy,
            opacity: max(0.0, min(1.0, opacity)),
            bounds: def.bounds,
            rows: rows,
            cols: cols,
            gridPoints: gridPoints
        )
    }

    @inline(__always)
    public static func transformPoint(
        x inX: Double,
        y inY: Double,
        through state: EvaluatedDeformerState
    ) -> (Double, Double) {
        switch state.type {
        case .rotation:
            let dx = (inX - state.pivotX) * state.scaleX
            let dy = (inY - state.pivotY) * state.scaleY
            let rad = state.angleDeg * (Double.pi / 180.0)
            let c = cos(rad)
            let s = sin(rad)
            let rx = dx * c - dy * s
            let ry = dx * s + dy * c
            return (state.pivotX + state.translateX + rx, state.pivotY + state.translateY + ry)

        case .warp:
            guard let b = state.bounds else { return (inX, inY) }
            let rawU = (inX - b.x) / b.width
            let rawV = (inY - b.y) / b.height
            let u = max(0.0, min(1.0, rawU))
            let v = max(0.0, min(1.0, rawV))
            let cols = state.cols
            let rows = state.rows
            let stride = cols + 1
            let su = u * Double(cols)
            let sv = v * Double(rows)
            let c0 = max(0, min(cols - 1, Int(floor(su))))
            let r0 = max(0, min(rows - 1, Int(floor(sv))))
            let fu = su - Double(c0)
            let fv = sv - Double(r0)

            let i00 = (r0 * stride + c0) * 2
            let i10 = (r0 * stride + c0 + 1) * 2
            let i01 = ((r0 + 1) * stride + c0) * 2
            let i11 = ((r0 + 1) * stride + c0 + 1) * 2
            let gp = state.gridPoints

            let topX = gp[i00] + (gp[i10] - gp[i00]) * fu
            let topY = gp[i00 + 1] + (gp[i10 + 1] - gp[i00 + 1]) * fu
            let botX = gp[i01] + (gp[i11] - gp[i01]) * fu
            let botY = gp[i01 + 1] + (gp[i11 + 1] - gp[i01 + 1]) * fu
            let warpedX = topX + (botX - topX) * fv
            let warpedY = topY + (botY - topY) * fv
            // Preserve in-bounds exact bilinear warp while applying clamped boundary displacement to out-of-bounds child vertices.
            let clampedInX = b.x + u * b.width
            let clampedInY = b.y + v * b.height
            return (inX + (warpedX - clampedInX), inY + (warpedY - clampedInY))
        }
    }

    public static func evaluateAll(
        avatar: SatLoadedAvatar,
        deformerStates: [String: EvaluatedDeformerState],
        meshBindingsById: [String: SatMeshBindingSpec],
        paramValues: [String: Double],
        drawableOpacityOverrides: [String: Double]? = nil
    ) -> [EvaluatedDrawable] {
        var out: [EvaluatedDrawable] = []
        out.reserveCapacity(avatar.model.drawables.count)

        let partVisible: [String: Bool] = {
            var m: [String: Bool] = [:]
            for p in avatar.model.parts ?? [] {
                m[p.id] = p.visible ?? true
            }
            return m
        }()
        let partOpacity: [String: Double] = {
            var m: [String: Double] = [:]
            for p in avatar.model.parts ?? [] {
                m[p.id] = p.opacity ?? 1.0
            }
            return m
        }()

        // Precompute parent chain for each deformer
        var chainCache: [String: [EvaluatedDeformerState]] = [:]
        func chain(for deformerId: String?) -> [EvaluatedDeformerState] {
            guard let id = deformerId else { return [] }
            if let cached = chainCache[id] { return cached }
            var list: [EvaluatedDeformerState] = []
            var cur: String? = id
            var safety = 0
            while let c = cur, safety < 64, let st = deformerStates[c] {
                list.append(st)
                cur = st.parent
                safety += 1
            }
            chainCache[id] = list
            return list
        }

        for dr in avatar.model.drawables {
            if dr.visible == false { continue }
            guard let mesh = avatar.meshes[dr.mesh] else { continue }
            let partId = dr.part ?? mesh.part
            if let pid = partId, partVisible[pid] == false { continue }

            let baseOpacity = (dr.opacity ?? mesh.opacity ?? 1.0)
                * (partId.flatMap { partOpacity[$0] } ?? 1.0)
                * (drawableOpacityOverrides?[dr.id] ?? 1.0)

            var meshOpacMult = 1.0
            var drawOrderOff = 0.0
            let vCount = mesh.vertices.count
            var pos = [Double](repeating: 0.0, count: vCount * 2)
            for i in 0..<vCount {
                pos[i * 2] = mesh.vertices[i][0]
                pos[i * 2 + 1] = mesh.vertices[i][1]
            }

            // 1. Direct mesh binding keyforms
            if let mb = meshBindingsById[mesh.id] {
                let samples = sampleAxes(axes: mb.axes, paramValues: paramValues)
                var opAcc = 0.0
                var tx = 0.0
                var ty = 0.0
                var sx = 0.0
                var sy = 0.0
                var pivX = 0.0
                var pivY = 0.0
                var hasCustomPivot = false

                for (kIdx, w) in samples where kIdx < mb.keyforms.count {
                    let kf = mb.keyforms[kIdx]
                    opAcc += (kf.opacity ?? 1.0) * w
                    drawOrderOff += (kf.drawOrderOffset ?? 0.0) * w
                    if let tr = kf.translate, tr.count >= 2 {
                        tx += tr[0] * w
                        ty += tr[1] * w
                    }
                    if let sc = kf.scale, sc.count >= 2 {
                        sx += sc[0] * w
                        sy += sc[1] * w
                    } else {
                        sx += 1.0 * w
                        sy += 1.0 * w
                    }
                    if let pv = kf.pivot, pv.count >= 2 {
                        pivX += pv[0] * w
                        pivY += pv[1] * w
                        hasCustomPivot = true
                    }
                    if let vd = kf.vertexDeltas, vd.count == vCount {
                        for i in 0..<vCount {
                            pos[i * 2] += vd[i][0] * w
                            pos[i * 2 + 1] += vd[i][1] * w
                        }
                    }
                }
                meshOpacMult = opAcc

                if !hasCustomPivot {
                    var sumX = 0.0, sumY = 0.0
                    for i in 0..<vCount {
                        sumX += pos[i * 2]
                        sumY += pos[i * 2 + 1]
                    }
                    pivX = sumX / Double(vCount)
                    pivY = sumY / Double(vCount)
                }

                if abs(tx) > 1e-6 || abs(ty) > 1e-6 || abs(sx - 1.0) > 1e-6 || abs(sy - 1.0) > 1e-6 {
                    for i in 0..<vCount {
                        pos[i * 2] = pivX + tx + (pos[i * 2] - pivX) * sx
                        pos[i * 2 + 1] = pivY + ty + (pos[i * 2 + 1] - pivY) * sy
                    }
                }
            }

            // 2. Deformer chain opacity & leaf-to-root transform
            let parentChain = chain(for: mesh.parent)
            var chainOpac = 1.0
            for st in parentChain {
                chainOpac *= st.opacity
            }
            let finalOpacity = Float(max(0.0, min(1.0, baseOpacity * meshOpacMult * chainOpac)))
            if finalOpacity <= 0.001 && (mesh.clipMasks?.isEmpty ?? true) {
                // Keep zero-opacity mask sources active just in case? Only skip if not referenced as mask!
                // We still evaluate position cleanly unless opacity == 0 is harmless.
            }

            if !parentChain.isEmpty {
                for i in 0..<vCount {
                    var x = pos[i * 2]
                    var y = pos[i * 2 + 1]
                    for st in parentChain {
                        (x, y) = transformPoint(x: x, y: y, through: st)
                    }
                    pos[i * 2] = x
                    pos[i * 2 + 1] = y
                }
            }

            var flatPos = [Float](repeating: 0.0, count: vCount * 2)
            var flatUV = [Float](repeating: 0.0, count: vCount * 2)
            var minU: Float = 1.0
            var minV: Float = 1.0
            var maxU: Float = 0.0
            var maxV: Float = 0.0
            for i in 0..<vCount {
                flatPos[i * 2] = Float(pos[i * 2])
                flatPos[i * 2 + 1] = Float(pos[i * 2 + 1])
                let u = Float(mesh.uv[i][0])
                let v = Float(mesh.uv[i][1])
                flatUV[i * 2] = u
                flatUV[i * 2 + 1] = v
                minU = min(minU, u)
                minV = min(minV, v)
                maxU = max(maxU, u)
                maxV = max(maxV, v)
            }
            let clipRect: [Float]
            if let r = mesh.uvClipRect, r.count == 4 {
                clipRect = [Float(r[0]), Float(r[1]), Float(r[2]), Float(r[3])]
            } else {
                clipRect = [0.0, 0.0, 1.0, 1.0]
            }

            out.append(EvaluatedDrawable(
                id: dr.id,
                meshId: mesh.id,
                textureFile: textureFile(for: mesh.texture, in: avatar.model) ?? "",
                positions: flatPos,
                uvs: flatUV,
                indices: mesh.triangles.map { UInt32($0) },
                drawOrder: (dr.drawOrder) + drawOrderOff,
                opacity: finalOpacity,
                blendMode: dr.blendMode ?? mesh.blendMode ?? .normal,
                clipMasks: mesh.clipMasks ?? [],
                invertedMask: mesh.invertedMask ?? false,
                uvClipRect: clipRect,
                doubleSided: dr.doubleSided ?? true
            ))
        }

        // Stable ascending drawOrder sort
        out.sort { lhs, rhs in
            if lhs.drawOrder != rhs.drawOrder {
                return lhs.drawOrder < rhs.drawOrder
            }
            return false
        }
        return out
    }

    private static func textureFile(for textureId: String, in layout: SatModelLayout) -> String? {
        layout.textures.first(where: { $0.id == textureId })?.file
    }
}
