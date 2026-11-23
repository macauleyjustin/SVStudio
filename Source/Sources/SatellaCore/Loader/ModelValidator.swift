import Foundation

public struct SatValidationReport: Sendable, Codable {
    public var valid: Bool
    public var errors: [String]
    public var warnings: [String]
    public var meshCount: Int
    public var totalVertices: Int
    public var totalTriangles: Int
    public var deformerCount: Int
    public var parameterCount: Int
    public var physicsGroupCount: Int
    public var expressionCount: Int
    public var animationCount: Int
    public var effectLayerCount: Int

    public init(
        valid: Bool,
        errors: [String],
        warnings: [String],
        meshCount: Int,
        totalVertices: Int,
        totalTriangles: Int,
        deformerCount: Int,
        parameterCount: Int,
        physicsGroupCount: Int,
        expressionCount: Int,
        animationCount: Int,
        effectLayerCount: Int
    ) {
        self.valid = valid
        self.errors = errors
        self.warnings = warnings
        self.meshCount = meshCount
        self.totalVertices = totalVertices
        self.totalTriangles = totalTriangles
        self.deformerCount = deformerCount
        self.parameterCount = parameterCount
        self.physicsGroupCount = physicsGroupCount
        self.expressionCount = expressionCount
        self.animationCount = animationCount
        self.effectLayerCount = effectLayerCount
    }
}

public enum ModelValidator {
    public static func validate(avatar: SatLoadedAvatar) -> SatValidationReport {
        var errors: [String] = []
        var warnings: [String] = []

        let m = avatar.manifest
        if m.format != "satella.avatar" {
            errors.append("Invalid manifest format '\(m.format)'; expected 'satella.avatar'.")
        }
        let semver = m.schemaVersion.split(separator: ".").compactMap { Int($0) }
        if semver.count != 3 {
            errors.append("Invalid schemaVersion '\(m.schemaVersion)'; expected SemVer X.Y.Z.")
        } else if semver[0] != 1 {
            errors.append("Unsupported schemaVersion major '\(m.schemaVersion)'; Satella supports 1.x.")
        }
        if !m.canvas.width.isFinite || !m.canvas.height.isFinite || m.canvas.width <= 0 || m.canvas.height <= 0 {
            errors.append("Invalid canvas size \(m.canvas.width)x\(m.canvas.height).")
        } else if m.canvas.width > Double(SatSecurityLimits.maxTextureSide) || m.canvas.height > Double(SatSecurityLimits.maxTextureSide) {
            errors.append("Canvas dimensions exceed limit \(SatSecurityLimits.maxTextureSide)px.")
        }

        // Textures
        var textureMap: [String: SatTextureSpec] = [:]
        for tex in avatar.model.textures {
            if textureMap[tex.id] != nil {
                errors.append("Duplicate texture ID '\(tex.id)'.")
            }
            textureMap[tex.id] = tex
            if tex.width <= 0 || tex.height <= 0 || tex.width > SatSecurityLimits.maxTextureSide || tex.height > SatSecurityLimits.maxTextureSide {
                errors.append("Texture '\(tex.id)' dimensions \(tex.width)x\(tex.height) out of bounds.")
            }
            if tex.width * tex.height > SatSecurityLimits.maxTexturePixels {
                errors.append("Texture '\(tex.id)' exceeds pixel cap.")
            }
            guard let pngBytes = avatar.textureData[tex.file] else {
                errors.append("Missing texture PNG data '\(tex.file)' for texture '\(tex.id)'.")
                continue
            }
            if let hdr = parsePngHeader(pngBytes) {
                if hdr.width != tex.width || hdr.height != tex.height {
                    errors.append("Texture '\(tex.file)' actual PNG size \(hdr.width)x\(hdr.height) disagrees with model.json \(tex.width)x\(tex.height).")
                }
            } else {
                errors.append("Texture '\(tex.file)' is not a valid PNG file.")
            }
        }

        // Parameters
        var paramMap: [String: SatParameterSpec] = [:]
        for p in avatar.rig.parameters {
            if p.id.isEmpty {
                errors.append("Empty parameter ID found in rig.json.")
                continue
            }
            if paramMap[p.id] != nil {
                errors.append("Duplicate parameter ID '\(p.id)'.")
            }
            if !p.min.isFinite || !p.default.isFinite || !p.max.isFinite {
                errors.append("Parameter '\(p.id)' contains non-finite values.")
            } else if !(p.min <= p.default && p.default <= p.max) {
                errors.append("Parameter '\(p.id)' violates min <= default <= max (\(p.min) <= \(p.default) <= \(p.max)).")
            }
            paramMap[p.id] = p
        }

        // Deformers & cycle detection
        var deformerMap: [String: SatDeformerSpec] = [:]
        for d in avatar.rig.deformers {
            if deformerMap[d.id] != nil {
                errors.append("Duplicate deformer ID '\(d.id)'.")
            }
            deformerMap[d.id] = d
        }
        for d in avatar.rig.deformers {
            if let p = d.parent, deformerMap[p] == nil {
                errors.append("Deformer '\(d.id)' references missing parent '\(p)'.")
            }
            switch d.type {
            case .rotation:
                if let piv = d.pivot {
                    if piv.count != 2 || !piv[0].isFinite || !piv[1].isFinite {
                        errors.append("Rotation deformer '\(d.id)' has invalid pivot.")
                    }
                } else {
                    errors.append("Rotation deformer '\(d.id)' requires a 2-element pivot.")
                }
            case .warp:
                guard let b = d.bounds, let rows = d.rows, let cols = d.cols else {
                    errors.append("Warp deformer '\(d.id)' requires bounds, rows, and cols.")
                    break
                }
                if !b.x.isFinite || !b.y.isFinite || !b.width.isFinite || !b.height.isFinite || b.width <= 0 || b.height <= 0 {
                    errors.append("Warp deformer '\(d.id)' has invalid bounds.")
                }
                if rows < 1 || rows > 32 || cols < 1 || cols > 32 {
                    errors.append("Warp deformer '\(d.id)' grid rows/cols out of range [1..32].")
                }
            }

            let expectedKf = validateAxes(d.axes ?? [], context: "Deformer '\(d.id)'", paramMap: paramMap, errors: &errors)
            let kfs = d.keyforms ?? []
            if !kfs.isEmpty && kfs.count != expectedKf {
                errors.append("Deformer '\(d.id)' has \(kfs.count) keyforms, expected \(expectedKf).")
            }
            if d.type == .warp, let rows = d.rows, let cols = d.cols {
                let gridCount = (rows + 1) * (cols + 1)
                for (ki, kf) in kfs.enumerated() {
                    if let offs = kf.gridOffsets {
                        if offs.count != gridCount {
                            errors.append("Warp deformer '\(d.id)' keyform[\(ki)] has \(offs.count) grid points, expected \(gridCount).")
                        } else if offs.contains(where: { $0.count != 2 || !$0[0].isFinite || !$0[1].isFinite }) {
                            errors.append("Warp deformer '\(d.id)' keyform[\(ki)] has malformed or non-finite offset.")
                        }
                    }
                }
            }
        }
        detectDeformerCycles(deformers: avatar.rig.deformers, errors: &errors)

        // Meshes & Drawables
        var drawableIds: Set<String> = []
        var meshIds: Set<String> = []
        var totalVerts = 0
        var totalTris = 0
        for dr in avatar.model.drawables {
            if !drawableIds.insert(dr.id).inserted {
                errors.append("Duplicate drawable ID '\(dr.id)'.")
            }
            if !dr.drawOrder.isFinite {
                errors.append("Drawable '\(dr.id)' has non-finite drawOrder.")
            }
            guard let mesh = avatar.meshes[dr.mesh] else {
                errors.append("Drawable '\(dr.id)' references missing mesh file '\(dr.mesh)'.")
                continue
            }
            if !meshIds.insert(mesh.id).inserted {
                errors.append("Duplicate mesh ID '\(mesh.id)'.")
            }
            if textureMap[mesh.texture] == nil {
                errors.append("Mesh '\(mesh.id)' references unknown texture '\(mesh.texture)'.")
            }
            if let parent = mesh.parent, deformerMap[parent] == nil {
                errors.append("Mesh '\(mesh.id)' references missing parent deformer '\(parent)'.")
            }
            if mesh.vertices.count < 3 || mesh.vertices.count > SatSecurityLimits.maxMeshVertices {
                errors.append("Mesh '\(mesh.id)' vertex count \(mesh.vertices.count) out of bounds.")
            }
            if mesh.uv.count != mesh.vertices.count {
                errors.append("Mesh '\(mesh.id)' UV count (\(mesh.uv.count)) != vertex count (\(mesh.vertices.count)).")
            }
            for (vi, v) in mesh.vertices.enumerated() {
                if v.count != 2 || !v[0].isFinite || !v[1].isFinite {
                    errors.append("Mesh '\(mesh.id)' vertex[\(vi)] invalid or non-finite.")
                    break
                }
            }
            for (ui, u) in mesh.uv.enumerated() {
                if u.count != 2 || !u[0].isFinite || !u[1].isFinite {
                    errors.append("Mesh '\(mesh.id)' uv[\(ui)] invalid or non-finite.")
                    break
                }
            }
            if mesh.triangles.count < 3 || mesh.triangles.count % 3 != 0 || mesh.triangles.count > SatSecurityLimits.maxMeshTrianglesIndices {
                errors.append("Mesh '\(mesh.id)' invalid triangle index count \(mesh.triangles.count).")
            } else {
                let vCount = mesh.vertices.count
                for idx in mesh.triangles {
                    if idx < 0 || idx >= vCount {
                        errors.append("Mesh '\(mesh.id)' triangle index \(idx) out of vertex bounds [0..<\(vCount)].")
                        break
                    }
                }
            }
            totalVerts += mesh.vertices.count
            totalTris += mesh.triangles.count / 3
        }

        // Check clip mask references exist
        for (_, mesh) in avatar.meshes {
            for maskId in mesh.clipMasks ?? [] {
                if !meshIds.contains(maskId) {
                    errors.append("Mesh '\(mesh.id)' clipMask '\(maskId)' does not exist.")
                }
                if maskId == mesh.id {
                    errors.append("Mesh '\(mesh.id)' cannot clip itself.")
                }
            }
        }

        // Mesh bindings
        for mb in avatar.rig.meshBindings ?? [] {
            guard let targetMesh = avatar.meshes.values.first(where: { $0.id == mb.meshId }) else {
                errors.append("meshBinding targets unknown meshId '\(mb.meshId)'.")
                continue
            }
            let expected = validateAxes(mb.axes, context: "meshBinding '\(mb.meshId)'", paramMap: paramMap, errors: &errors)
            if mb.keyforms.count != expected {
                errors.append("meshBinding '\(mb.meshId)' has \(mb.keyforms.count) keyforms, expected \(expected).")
            }
            for (ki, kf) in mb.keyforms.enumerated() {
                if let vd = kf.vertexDeltas {
                    if vd.count != targetMesh.vertices.count {
                        errors.append("meshBinding '\(mb.meshId)' keyform[\(ki)] vertexDeltas count \(vd.count) != mesh vertices \(targetMesh.vertices.count).")
                    } else if vd.contains(where: { $0.count != 2 || !$0[0].isFinite || !$0[1].isFinite }) {
                        errors.append("meshBinding '\(mb.meshId)' keyform[\(ki)] has non-finite vertex delta.")
                    }
                }
            }
        }

        // Avatar-defined drag reactions
        for dr in avatar.rig.dragReactions ?? [] {
            if paramMap[dr.parameter] == nil {
                warnings.append("dragReaction '\(dr.id)' references unknown parameter '\(dr.parameter)'.")
            }
            if !dr.targetValue.isFinite {
                errors.append("dragReaction '\(dr.id)' has non-finite targetValue.")
            }
        }

        // Physics
        if let phys = avatar.physics {
            if !phys.fixedTimestep.isFinite || phys.fixedTimestep <= 0 || phys.fixedTimestep > 0.1 {
                errors.append("physics.json invalid fixedTimestep \(phys.fixedTimestep).")
            }
            for g in phys.groups {
                if let st = g.stiffness, (!st.isFinite || st <= 0) {
                    errors.append("Physics group '\(g.id)' non-positive stiffness.")
                }
                if let dp = g.damping, (!dp.isFinite || dp < 0) {
                    errors.append("Physics group '\(g.id)' negative damping.")
                }
                if g.type == .pendulum && (g.nodes?.isEmpty ?? true) {
                    errors.append("Pendulum physics group '\(g.id)' requires nodes.")
                }
                for inp in g.inputs where paramMap[inp.parameter] == nil {
                    errors.append("Physics group '\(g.id)' input parameter '\(inp.parameter)' missing in rig.json.")
                }
                for outp in g.outputs where paramMap[outp.parameter] == nil {
                    errors.append("Physics group '\(g.id)' output parameter '\(outp.parameter)' missing in rig.json.")
                }
            }
        }

        // Expressions & animations
        for exp in avatar.expressions {
            for p in exp.parameters where paramMap[p.parameter] == nil {
                warnings.append("Expression '\(exp.id)' references unknown parameter '\(p.parameter)'.")
            }
        }
        for anim in avatar.animations {
            if anim.duration <= 0 || !anim.duration.isFinite {
                errors.append("Animation '\(anim.id)' invalid duration \(anim.duration).")
            }
            for tr in anim.tracks where paramMap[tr.parameter] == nil {
                warnings.append("Animation '\(anim.id)' track references unknown parameter '\(tr.parameter)'.")
            }
        }

        let effectCount = avatar.effects.reduce(0) { $0 + $1.layers.count }
        for fx in avatar.effects {
            for layer in fx.layers {
                if let p = layer.intensityParam, paramMap[p] == nil {
                    warnings.append("Effect '\(layer.id)' references unknown parameter '\(p)'.")
                }
                if let d = layer.followDeformer, deformerMap[d] == nil {
                    errors.append("Effect '\(layer.id)' references missing deformer '\(d)'.")
                }
                if let tex = layer.texture, avatar.textureData[tex] == nil {
                    errors.append("Effect '\(layer.id)' references missing texture file '\(tex)'.")
                }
            }
        }

        return SatValidationReport(
            valid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            meshCount: avatar.meshes.count,
            totalVertices: totalVerts,
            totalTriangles: totalTris,
            deformerCount: avatar.rig.deformers.count,
            parameterCount: avatar.rig.parameters.count,
            physicsGroupCount: avatar.physics?.groups.count ?? 0,
            expressionCount: avatar.expressions.count,
            animationCount: avatar.animations.count,
            effectLayerCount: effectCount
        )
    }

    private static func validateAxes(
        _ axes: [SatAxisSpec],
        context: String,
        paramMap: [String: SatParameterSpec],
        errors: inout [String]
    ) -> Int {
        var total = 1
        for axis in axes {
            if paramMap[axis.parameter] == nil {
                errors.append("\(context) references unknown parameter '\(axis.parameter)'.")
            }
            if axis.keys.isEmpty {
                errors.append("\(context) axis '\(axis.parameter)' has no keys.")
                continue
            }
            for i in 0..<axis.keys.count {
                if !axis.keys[i].isFinite {
                    errors.append("\(context) axis '\(axis.parameter)' has non-finite key.")
                }
                if i > 0 && axis.keys[i] <= axis.keys[i - 1] {
                    errors.append("\(context) axis '\(axis.parameter)' keys must be strictly ascending.")
                }
            }
            total *= axis.keys.count
        }
        return total
    }

    private static func detectDeformerCycles(deformers: [SatDeformerSpec], errors: inout [String]) {
        var parentOf: [String: String] = [:]
        for d in deformers {
            if let p = d.parent {
                parentOf[d.id] = p
            }
        }
        enum State { case visiting, visited }
        var state: [String: State] = [:]
        for d in deformers {
            if state[d.id] == .visited { continue }
            var chain: [String] = []
            var cur: String? = d.id
            while let id = cur {
                if state[id] == .visited { break }
                if state[id] == .visiting {
                    errors.append("Deformer hierarchy cycle detected involving '\(id)' (\(chain.joined(separator: " -> ")) -> \(id)).")
                    break
                }
                state[id] = .visiting
                chain.append(id)
                cur = parentOf[id]
            }
            for id in chain {
                state[id] = .visited
            }
        }
    }

    public static func parsePngHeader(_ data: Data) -> (width: Int, height: Int)? {
        let sig: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.count >= 24 else { return nil }
        for i in 0..<8 where data[i] != sig[i] {
            return nil
        }
        guard data[12] == 73 && data[13] == 72 && data[14] == 68 && data[15] == 82 else {
            return nil
        }
        let w = (Int(data[16]) << 24) | (Int(data[17]) << 16) | (Int(data[18]) << 8) | Int(data[19])
        let h = (Int(data[20]) << 24) | (Int(data[21]) << 16) | (Int(data[22]) << 8) | Int(data[23])
        return (w, h)
    }
}
