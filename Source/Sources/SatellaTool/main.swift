import Foundation
import CoreGraphics
import ImageIO
import SatellaCore
import SatellaRender

struct ToolUsageError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func printUsage() {
    print("""
    svstudio-tool — External CLI utility for SVStudio (.sat) avatars

    Usage:
      svstudio-tool validate <avatar.sat | folder/>
      svstudio-tool pack <folder/> [-o <output.sat>]
      svstudio-tool inspect <avatar.sat | folder/> [--json]
      svstudio-tool render <avatar.sat | folder/> [options]
      svstudio-tool test <avatar.sat | folder/> [--out-dir <dir>]
      svstudio-tool automesh <png> --id <meshId> --texture <texId> --out <mesh.json> [options]

    Render Options:
      --out <file.png>          Output PNG path (default: render.png)
      --background <mode>       black | green | white | checkerboard | transparent
      --expression <id>         Activate expression ID
      --param <ID=VALUE>        Override parameter (repeatable)
      --width <px>              Output image width (default: canvas width)
      --height <px>             Output image height (default: canvas height)
      --zoom <factor>           Camera zoom (default: 1.0)
      --pan-x <px>              Camera horizontal pan in pixels (default: 0.0)
      --pan-y <px>              Camera vertical pan in pixels (default: 0.0)
      --time <seconds>          Advance simulation/animation time (default: 0.0)
    """)
}

func resolveBackground(_ raw: String) -> SatBackgroundMode {
    switch raw.lowercased() {
    case "green", "greenscreen", "green_screen": return .greenScreen
    case "white": return .white
    case "checker", "checkerboard": return .checkerboard
    case "transparent", "alpha": return .transparent
    default: return .black
    }
}

func decodePNGAlpha(_ url: URL) throws -> (width: Int, height: Int, alpha: [UInt8]) {
    let data = try Data(contentsOf: url)
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw ToolUsageError(message: "Unable to decode PNG at \(url.path)")
    }
    let w = cg.width
    let h = cg.height
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: info.rawValue) else {
        throw ToolUsageError(message: "Unable to create CGContext for \(url.path)")
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var alpha = [UInt8](repeating: 0, count: w * h)
    for i in 0..<(w * h) {
        alpha[i] = rgba[i * 4 + 3]
    }
    return (w, h, alpha)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else {
        printUsage()
        exit(0)
    }

    switch cmd {
    case "validate":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing input path for validate.") }
        let url = URL(fileURLWithPath: args[1])
        let (avatar, report) = try ModelLoader.loadAllowingInvalid(url: url)
        print("Avatar: \(avatar.manifest.name) (\(avatar.manifest.id)) schema=\(avatar.manifest.schemaVersion)")
        print("Summary: meshes=\(report.meshCount), vertices=\(report.totalVertices), triangles=\(report.totalTriangles), deformers=\(report.deformerCount), parameters=\(report.parameterCount), physicsGroups=\(report.physicsGroupCount), expressions=\(report.expressionCount), animations=\(report.animationCount), effectLayers=\(report.effectLayerCount)")
        for w in report.warnings {
            print("  WARNING: \(w)")
        }
        if !report.valid {
            for e in report.errors {
                fputs("  ERROR: \(e)\n", stderr)
            }
            exit(2)
        }
        print("VALIDATION PASSED (0 errors).")

    case "pack":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing folder path for pack.") }
        let folder = URL(fileURLWithPath: args[1])
        var outPath = folder.lastPathComponent + ".sat"
        var i = 2
        while i < args.count {
            if args[i] == "-o" || args[i] == "--out", i + 1 < args.count {
                outPath = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        let outURL = URL(fileURLWithPath: outPath)
        let report = try ModelLoader.packDirectory(folder, to: outURL)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? NSNumber)?.intValue ?? 0
        print("Packed \(outURL.path) (\(bytes) bytes): meshes=\(report.meshCount), verts=\(report.totalVertices), tris=\(report.totalTriangles)")

    case "inspect":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing input path for inspect.") }
        let url = URL(fileURLWithPath: args[1])
        let jsonMode = args.contains("--json")
        let (avatar, report) = try ModelLoader.loadAndValidate(url: url)
        if jsonMode {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct InspectOut: Codable {
                var manifest: SatManifest
                var report: SatValidationReport
                var parameters: [SatParameterSpec]
                var drawables: [String]
                var deformers: [String]
            }
            let out = InspectOut(
                manifest: avatar.manifest,
                report: report,
                parameters: avatar.rig.parameters,
                drawables: avatar.model.drawables.map { $0.id },
                deformers: avatar.rig.deformers.map { "\($0.id) (\($0.type.rawValue))" }
            )
            let data = try encoder.encode(out)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("=== \(avatar.manifest.name) [\(avatar.manifest.id)] ===")
            print("Canvas: \(Int(avatar.manifest.canvas.width))x\(Int(avatar.manifest.canvas.height))")
            print("Features: \(String(describing: avatar.manifest.features))")
            print("Textures (\(avatar.model.textures.count)): " + avatar.model.textures.map { "\($0.id) (\($0.width)x\($0.height))" }.joined(separator: ", "))
            print("Drawables (\(avatar.model.drawables.count)), Meshes (\(report.meshCount)), Vertices (\(report.totalVertices)), Triangles (\(report.totalTriangles))")
            print("Deformers (\(avatar.rig.deformers.count)): " + avatar.rig.deformers.map { $0.id }.joined(separator: ", "))
            print("Parameters (\(avatar.rig.parameters.count)): " + avatar.rig.parameters.map { "\($0.id)[\($0.min)..\($0.default)..\($0.max)]" }.joined(separator: ", "))
            print("Expressions (\(avatar.expressions.count)): " + avatar.expressions.map { $0.id }.joined(separator: ", "))
            print("Animations (\(avatar.animations.count)): " + avatar.animations.map { $0.id }.joined(separator: ", "))
            print("Physics groups (\(report.physicsGroupCount)): " + (avatar.physics?.groups.map { $0.id }.joined(separator: ", ") ?? "none"))
            print("Effect layers (\(report.effectLayerCount))")
        }

    case "render":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing input path for render.") }
        let url = URL(fileURLWithPath: args[1])
        let (avatar, _) = try ModelLoader.loadAndValidate(url: url)

        var outPath = "render.png"
        var bg: SatBackgroundMode = .black
        var expId: String? = nil
        var overrides: [String: Double] = [:]
        var outW = Int(avatar.manifest.canvas.width.rounded())
        var outH = Int(avatar.manifest.canvas.height.rounded())
        var zoom: Float = 1.0
        var panX: Float = 0.0
        var panY: Float = 0.0
        var simTime: Double = 0.0

        var i = 2
        while i < args.count {
            switch args[i] {
            case "--out", "-o":
                outPath = args[i + 1]; i += 2
            case "--background", "-bg":
                bg = resolveBackground(args[i + 1]); i += 2
            case "--expression", "-e":
                expId = args[i + 1]; i += 2
            case "--width":
                outW = Int(args[i + 1]) ?? outW; i += 2
            case "--height":
                outH = Int(args[i + 1]) ?? outH; i += 2
            case "--zoom":
                zoom = Float(args[i + 1]) ?? 1.0; i += 2
            case "--pan-x":
                panX = Float(args[i + 1]) ?? 0.0; i += 2
            case "--pan-y":
                panY = Float(args[i + 1]) ?? 0.0; i += 2
            case "--time":
                simTime = Double(args[i + 1]) ?? 0.0; i += 2
            case "--param", "-p":
                let kv = args[i + 1].split(separator: "=", maxSplits: 1)
                if kv.count == 2, let val = Double(kv[1]) {
                    overrides[String(kv[0])] = val
                }
                i += 2
            default:
                i += 1
            }
        }

        let rig = RigController(avatar: avatar)
        rig.animationsEnabled = simTime > 0
        if let e = expId {
            rig.expressionController.select(expressionId: e)
            // Fast-forward fade
            _ = rig.step(dt: 1.0)
        }
        for (k, v) in overrides {
            rig.manualOverrides[k] = v
        }
        let steps = max(1, Int((simTime * 60.0).rounded()))
        var result = rig.step(dt: 1.0 / 60.0)
        if simTime > 0 {
            for _ in 1..<steps {
                result = rig.step(dt: 1.0 / 60.0)
            }
        }

        let engine = try RenderEngine()
        try engine.renderOffscreenToPNG(
            avatar: avatar,
            drawables: result.drawables,
            effects: result.effects,
            width: outW,
            height: outH,
            camera: SatCameraTransform(zoom: zoom, panX: panX, panY: panY),
            background: bg,
            outputURL: URL(fileURLWithPath: outPath)
        )
        print("Rendered \(outPath) (\(outW)x\(outH), bg=\(bg.rawValue), drawables=\(result.drawables.count), effectGroups=\(result.effects.count))")

    case "test":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing input path for test.") }
        let url = URL(fileURLWithPath: args[1])
        var outDir = "satella_test_out"
        if let idx = args.firstIndex(of: "--out-dir"), idx + 1 < args.count {
            outDir = args[idx + 1]
        }
        let outURL = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        let (avatar, report) = try ModelLoader.loadAndValidate(url: url)
        let engine = try RenderEngine()
        let outW = Int(avatar.manifest.canvas.width.rounded())
        let outH = Int(avatar.manifest.canvas.height.rounded())

        func runPose(_ name: String, bg: SatBackgroundMode = .checkerboard, exp: String? = nil, params: [String: Double] = [:], simSeconds: Double = 0.05) throws {
            let rig = RigController(avatar: avatar)
            rig.animationsEnabled = false
            if let exp = exp {
                rig.expressionController.select(expressionId: exp)
                _ = rig.step(dt: 2.0)
            }
            for (k, v) in params {
                rig.manualOverrides[k] = v
            }
            var res = rig.step(dt: 1.0 / 60.0)
            let steps = max(1, Int((simSeconds * 60.0).rounded()))
            for _ in 0..<steps {
                res = rig.step(dt: 1.0 / 60.0)
            }
            for dr in res.drawables {
                if dr.positions.contains(where: { !$0.isFinite }) {
                    throw ToolUsageError(message: "Non-finite vertex detected in pose '\(name)' on mesh '\(dr.meshId)'")
                }
            }
            let png = outURL.appendingPathComponent("\(name).png")
            try engine.renderOffscreenToPNG(
                avatar: avatar, drawables: res.drawables, effects: res.effects,
                width: outW, height: outH, background: bg, outputURL: png
            )
            print("  [PASS] \(name).png (drawables=\(res.drawables.count), effects=\(res.effects.count))")
        }

        try runPose("01_neutral_black", bg: .black)
        try runPose("02_neutral_green", bg: .greenScreen)
        try runPose("03_neutral_checker", bg: .checkerboard)
        try runPose("04_neutral_white", bg: .white)

        let stdMinMax: [(String, Double, Double)] = [
            ("ParamAngleX", -30, 30),
            ("ParamAngleY", -30, 30),
            ("ParamAngleZ", -25, 25),
            ("ParamMouthOpenY", 0, 1),
            ("ParamMouthForm", -1, 1),
            ("ParamBodyAngleX", -10, 10)
        ]
        for (pid, pmin, pmax) in stdMinMax where avatar.rig.parameters.contains(where: { $0.id == pid }) {
            let clean = pid.replacingOccurrences(of: "Param", with: "")
            if pmin != 0 {
                try runPose("pose_\(clean)_min", bg: .black, params: [pid: pmin])
            }
            try runPose("pose_\(clean)_max", bg: .black, params: [pid: pmax])
        }
        for exp in avatar.expressions {
            try runPose("exp_\(exp.id)", bg: .black, exp: exp.id)
        }

        // Verify physics excitation & return-to-rest settling
        if avatar.physics != nil {
            let rig = RigController(avatar: avatar)
            rig.animationsEnabled = false
            rig.manualOverrides["ParamAngleX"] = 30.0
            rig.manualOverrides["ParamBodyAngleY"] = 10.0
            for _ in 0..<20 { _ = rig.step(dt: 1.0 / 60.0) }
            rig.manualOverrides.removeAll()
            for _ in 0..<240 { _ = rig.step(dt: 1.0 / 60.0) }
            for g in avatar.physics?.groups ?? [] {
                for o in g.outputs {
                    let settled = rig.paramValues[o.parameter] ?? 0.0
                    let def = rig.paramMeta[o.parameter]?.default ?? 0.0
                    if abs(settled - def) > 0.08 {
                        throw ToolUsageError(message: "Physics parameter '\(o.parameter)' failed to settle cleanly (val=\(settled), def=\(def)).")
                    }
                }
            }
            print("  [PASS] physics_settle (all groups returned within 0.08 of equilibrium after 4s)")
        }

        print("ALL SELF-TESTS PASSED for \(avatar.manifest.name) (meshes=\(report.meshCount), verts=\(report.totalVertices)) -> \(outURL.path)")

    case "automesh":
        guard args.count >= 2 else { throw ToolUsageError(message: "Missing PNG path for automesh.") }
        let pngURL = URL(fileURLWithPath: args[1])
        var id = "mesh"
        var texId = "tex"
        var parent: String? = nil
        var outPath = "mesh.json"
        var spacing = 24.0
        var inner = 28.0
        var pad = 8.0
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--id": id = args[i + 1]; i += 2
            case "--texture": texId = args[i + 1]; i += 2
            case "--parent": parent = args[i + 1]; i += 2
            case "--out": outPath = args[i + 1]; i += 2
            case "--spacing": spacing = Double(args[i + 1]) ?? 24.0; i += 2
            case "--inner": inner = Double(args[i + 1]) ?? 28.0; i += 2
            case "--padding": pad = Double(args[i + 1]) ?? 8.0; i += 2
            default: i += 1
            }
        }
        let (w, h, alpha) = try decodePNGAlpha(pngURL)
        let mesh = SatAutoMesher.generateMesh(
            id: id, textureId: texId, parentDeformer: parent, partId: nil, drawOrder: 100,
            imgWidth: w, imgHeight: h,
            params: SatAutoMeshParams(outlineSpacing: spacing, innerSpacing: inner, padding: pad)
        ) { x, y in alpha[y * w + x] }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        try enc.encode(mesh).write(to: URL(fileURLWithPath: outPath))
        print("Generated mesh '\(id)': \(mesh.vertices.count) vertices, \(mesh.triangles.count / 3) triangles -> \(outPath)")

    default:
        printUsage()
        exit(cmd == "--help" || cmd == "-h" ? 0 : 1)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
