import Foundation

public enum ModelLoaderError: Error, LocalizedError, Sendable {
    case invalidPackage(String)
    case validationFailed([String])

    public var errorDescription: String? {
        switch self {
        case .invalidPackage(let msg):
            return msg
        case .validationFailed(let errs):
            return "Avatar validation failed with \(errs.count) error(s):\n" + errs.joined(separator: "\n")
        }
    }
}

public enum ModelLoader {
    public static func loadAndValidate(url: URL) throws -> (avatar: SatLoadedAvatar, report: SatValidationReport) {
        let archive: ZipArchive
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            archive = try readDirectoryAsArchive(url)
        } else {
            archive = try ZipArchive.read(from: url)
        }
        let avatar = try decode(archive: archive, sourceURL: url)
        let report = ModelValidator.validate(avatar: avatar)
        if !report.valid {
            throw ModelLoaderError.validationFailed(report.errors)
        }
        return (avatar, report)
    }

    public static func loadAllowingInvalid(url: URL) throws -> (avatar: SatLoadedAvatar, report: SatValidationReport) {
        let archive: ZipArchive
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            archive = try readDirectoryAsArchive(url)
        } else {
            archive = try ZipArchive.read(from: url)
        }
        let avatar = try decode(archive: archive, sourceURL: url)
        let report = ModelValidator.validate(avatar: avatar)
        return (avatar, report)
    }

    public static func packDirectory(_ folderURL: URL, to outputURL: URL) throws -> SatValidationReport {
        let archive = try readDirectoryAsArchive(folderURL)
        let avatar = try decode(archive: archive, sourceURL: folderURL)
        let report = ModelValidator.validate(avatar: avatar)
        if !report.valid {
            throw ModelLoaderError.validationFailed(report.errors)
        }
        try archive.write(to: outputURL)
        return report
    }

    public static func readDirectoryAsArchive(_ dir: URL) throws -> ZipArchive {
        let fm = FileManager.default
        let base = dir.standardizedFileURL.path
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw ModelLoaderError.invalidPackage("Cannot read directory \(dir.path)")
        }
        var entries: [String: Data] = [:]
        while let obj = enumerator.nextObject() as? URL {
            let vals = try obj.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if vals.isSymbolicLink == true {
                throw SatArchiveError.unsafePath(obj.path)
            }
            guard vals.isRegularFile == true else { continue }
            let full = obj.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            if rel.hasPrefix(".DS_Store") || rel.hasSuffix("/.DS_Store") || rel.hasPrefix("__MACOSX") {
                continue
            }
            let safe = try SatSecurityLimits.validateRelativePath(rel)
            entries[safe] = try Data(contentsOf: obj)
        }
        return ZipArchive(entries: entries)
    }

    private static func decode(archive: ZipArchive, sourceURL: URL?) throws -> SatLoadedAvatar {
        let decoder = JSONDecoder()

        func decodeJSON<T: Decodable>(_ type: T.Type, path: String) throws -> T {
            let safe = try SatSecurityLimits.validateRelativePath(path)
            guard let data = archive.entries[safe] else {
                throw SatArchiveError.missingEntry(safe)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ModelLoaderError.invalidPackage("Failed to decode '\(safe)': \(error.localizedDescription)")
            }
        }

        let manifest = try decodeJSON(SatManifest.self, path: "manifest.json")
        let model = try decodeJSON(SatModelLayout.self, path: manifest.model)
        let rig = try decodeJSON(SatRig.self, path: manifest.rig)
        let physics: SatPhysicsSpec? = try manifest.physics.map { try decodeJSON(SatPhysicsSpec.self, path: $0) }

        var meshes: [String: SatMesh] = [:]
        for dr in model.drawables {
            if meshes[dr.mesh] == nil {
                meshes[dr.mesh] = try decodeJSON(SatMesh.self, path: dr.mesh)
            }
        }

        var textureData: [String: Data] = [:]
        for tex in model.textures {
            let safeTex = try SatSecurityLimits.validateRelativePath(tex.file)
            guard let bytes = archive.entries[safeTex] else {
                throw SatArchiveError.missingEntry(safeTex)
            }
            textureData[safeTex] = bytes
        }

        var expressions: [SatExpression] = []
        for eref in manifest.expressions ?? [] {
            expressions.append(try decodeJSON(SatExpression.self, path: eref.file))
        }

        var animations: [SatAnimation] = []
        for aref in manifest.animations ?? [] {
            animations.append(try decodeJSON(SatAnimation.self, path: aref.file))
        }

        var effects: [SatEffectsSpec] = []
        for fxref in manifest.effects ?? [] {
            let spec = try decodeJSON(SatEffectsSpec.self, path: fxref.file)
            for layer in spec.layers {
                if let texPath = layer.texture {
                    let safeTex = try SatSecurityLimits.validateRelativePath(texPath)
                    if let bytes = archive.entries[safeTex] {
                        textureData[safeTex] = bytes
                    } else {
                        throw SatArchiveError.missingEntry(safeTex)
                    }
                }
            }
            effects.append(spec)
        }

        return SatLoadedAvatar(
            sourceURL: sourceURL,
            manifest: manifest,
            model: model,
            rig: rig,
            physics: physics,
            meshes: meshes,
            textureData: textureData,
            expressions: expressions,
            animations: animations,
            effects: effects
        )
    }
}
