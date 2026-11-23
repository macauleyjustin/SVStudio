import Foundation
import CZlib

public enum SatArchiveError: Error, LocalizedError, Sendable {
    case fileTooLarge(Int)
    case invalidArchive(String)
    case entryLimitExceeded(Int)
    case decompressionBomb(String)
    case unsafePath(String)
    case disallowedFileType(String)
    case missingEntry(String)
    case crcMismatch(String)
    case compressionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let bytes):
            return "Archive exceeds maximum permitted size (\(bytes) bytes > \(SatSecurityLimits.maxArchiveBytes) bytes)."
        case .invalidArchive(let reason):
            return "Invalid .sat ZIP archive: \(reason)"
        case .entryLimitExceeded(let count):
            return "Archive contains too many entries (\(count) > \(SatSecurityLimits.maxEntryCount))."
        case .decompressionBomb(let path):
            return "Rejected entry '\(path)' due to decompression bomb or oversized payload limits."
        case .unsafePath(let path):
            return "Rejected unsafe path '\(path)' (path traversal, absolute path, or symlink)."
        case .disallowedFileType(let path):
            return "Rejected disallowed executable or script file '\(path)' inside .sat archive."
        case .missingEntry(let path):
            return "Missing required archive entry '\(path)'."
        case .crcMismatch(let path):
            return "CRC-32 checksum mismatch while reading '\(path)'."
        case .compressionFailed(let reason):
            return "Archive compression failed: \(reason)"
        }
    }
}

public enum SatSecurityLimits {
    public static let maxArchiveBytes = 512 * 1024 * 1024
    public static let maxEntryCount = 4096
    public static let maxEntryUncompressedBytes = 128 * 1024 * 1024
    public static let maxTotalUncompressedBytes = 768 * 1024 * 1024
    public static let maxTextureSide = 8192
    public static let maxTexturePixels = 67_108_864
    public static let maxMeshVertices = 65_535
    public static let maxMeshTrianglesIndices = 300_000
    public static let forbiddenExtensions: Set<String> = [
        "sh", "zsh", "bash", "py", "pyc", "js", "mjs", "cjs", "ts",
        "dylib", "so", "dll", "exe", "app", "command", "pkg", "dmg",
        "rb", "pl", "php", "bat", "ps1", "vbs", "swift"
    ]

    public static func validateRelativePath(_ rawPath: String) throws -> String {
        if rawPath.isEmpty || rawPath.contains("\0") || rawPath.contains("\\") {
            throw SatArchiveError.unsafePath(rawPath)
        }
        if rawPath.hasPrefix("/") {
            throw SatArchiveError.unsafePath(rawPath)
        }
        if rawPath.contains(":") {
            throw SatArchiveError.unsafePath(rawPath)
        }
        let clean = rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath
        let parts = clean.split(separator: "/", omittingEmptySubsequences: false)
        for seg in parts {
            if seg.isEmpty || seg == "." || seg == ".." {
                throw SatArchiveError.unsafePath(rawPath)
            }
        }
        let ext = (clean as NSString).pathExtension.lowercased()
        if !ext.isEmpty && forbiddenExtensions.contains(ext) {
            throw SatArchiveError.disallowedFileType(clean)
        }
        return clean
    }
}

public struct ZipArchive: Sendable {
    public var entries: [String: Data]

    public init(entries: [String: Data] = [:]) {
        self.entries = entries
    }

    public static func read(from url: URL) throws -> ZipArchive {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = (attrs[.size] as? NSNumber)?.intValue, size > SatSecurityLimits.maxArchiveBytes {
            throw SatArchiveError.fileTooLarge(size)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try read(data: data)
    }

    public static func read(data: Data) throws -> ZipArchive {
        if data.count > SatSecurityLimits.maxArchiveBytes {
            throw SatArchiveError.fileTooLarge(data.count)
        }
        if data.count < 22 {
            throw SatArchiveError.invalidArchive("File shorter than ZIP End-of-Central-Directory record.")
        }

        // Locate EOCD signature 0x06054b50 scanning backwards up to 65557 bytes
        let minOffset = max(0, data.count - 65557)
        var eocdOffset: Int? = nil
        var cursor = data.count - 22
        while cursor >= minOffset {
            if readU32(data, cursor) == 0x0605_4b50 {
                let commentLen = Int(readU16(data, cursor + 20))
                if cursor + 22 + commentLen == data.count {
                    eocdOffset = cursor
                    break
                }
            }
            cursor -= 1
        }
        guard let eocd = eocdOffset else {
            throw SatArchiveError.invalidArchive("Missing ZIP End-of-Central-Directory signature.")
        }

        let totalEntries = Int(readU16(data, eocd + 10))
        let cdSize = Int(readU32(data, eocd + 12))
        let cdOffset = Int(readU32(data, eocd + 16))
        if totalEntries > SatSecurityLimits.maxEntryCount {
            throw SatArchiveError.entryLimitExceeded(totalEntries)
        }
        if cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > eocd {
            throw SatArchiveError.invalidArchive("Corrupt Central Directory bounds.")
        }

        var result: [String: Data] = [:]
        var totalUncompressed = 0
        var off = cdOffset

        for _ in 0..<totalEntries {
            if off + 46 > cdOffset + cdSize || readU32(data, off) != 0x0201_4b50 {
                throw SatArchiveError.invalidArchive("Malformed Central Directory entry header.")
            }
            let method = readU16(data, off + 10)
            let expectedCRC = readU32(data, off + 16)
            let compSize = Int(readU32(data, off + 20))
            let uncompSize = Int(readU32(data, off + 24))
            let nameLen = Int(readU16(data, off + 28))
            let extraLen = Int(readU16(data, off + 30))
            let commentLen = Int(readU16(data, off + 32))
            let extAttr = readU32(data, off + 38)
            let localOffset = Int(readU32(data, off + 42))

            if off + 46 + nameLen + extraLen + commentLen > cdOffset + cdSize {
                throw SatArchiveError.invalidArchive("Central Directory record overflows bounds.")
            }
            let nameData = data.subdata(in: (off + 46)..<(off + 46 + nameLen))
            guard let rawName = String(data: nameData, encoding: .utf8) else {
                throw SatArchiveError.invalidArchive("Non-UTF8 ZIP filename.")
            }
            off += 46 + nameLen + extraLen + commentLen

            // Reject symlinks (POSIX S_IFLNK = 0o120000 in upper 16 bits)
            let posixMode = (extAttr >> 16) & 0o170000
            if posixMode == 0o120000 {
                throw SatArchiveError.unsafePath(rawName)
            }

            if rawName.hasSuffix("/") && uncompSize == 0 {
                // Validate folder path is safe anyway
                let trimmed = String(rawName.dropLast())
                if !trimmed.isEmpty {
                    _ = try SatSecurityLimits.validateRelativePath(trimmed)
                }
                continue
            }

            let safePath = try SatSecurityLimits.validateRelativePath(rawName)
            if uncompSize < 0 || compSize < 0 || uncompSize > SatSecurityLimits.maxEntryUncompressedBytes {
                throw SatArchiveError.decompressionBomb(safePath)
            }
            if uncompSize > 1_048_576 && compSize > 0 && (uncompSize / compSize) > 100 {
                throw SatArchiveError.decompressionBomb(safePath)
            }
            totalUncompressed += uncompSize
            if totalUncompressed > SatSecurityLimits.maxTotalUncompressedBytes {
                throw SatArchiveError.decompressionBomb(safePath)
            }

            if localOffset < 0 || localOffset + 30 > data.count || readU32(data, localOffset) != 0x0403_4b50 {
                throw SatArchiveError.invalidArchive("Corrupt Local File Header for '\(safePath)'.")
            }
            let lNameLen = Int(readU16(data, localOffset + 26))
            let lExtraLen = Int(readU16(data, localOffset + 28))
            let payloadStart = localOffset + 30 + lNameLen + lExtraLen
            let payloadEnd = payloadStart + compSize
            if payloadEnd > data.count {
                throw SatArchiveError.invalidArchive("Compressed payload truncated for '\(safePath)'.")
            }

            let payloadSlice = data[payloadStart..<payloadEnd]
            let decoded: Data
            switch method {
            case 0:
                if compSize != uncompSize {
                    throw SatArchiveError.invalidArchive("STORED size mismatch for '\(safePath)'.")
                }
                decoded = Data(payloadSlice)
            case 8:
                var out = Data(count: uncompSize)
                var actualLen = 0
                let rc = payloadSlice.withUnsafeBytes { srcPtr in
                    out.withUnsafeMutableBytes { dstPtr in
                        sat_inflate_raw(
                            srcPtr.bindMemory(to: UInt8.self).baseAddress,
                            compSize,
                            dstPtr.bindMemory(to: UInt8.self).baseAddress,
                            uncompSize,
                            &actualLen
                        )
                    }
                }
                if rc != 0 || actualLen != uncompSize {
                    throw SatArchiveError.decompressionBomb(safePath)
                }
                decoded = out
            default:
                throw SatArchiveError.invalidArchive("Unsupported ZIP compression method \(method) for '\(safePath)'.")
            }

            let actualCRC = decoded.withUnsafeBytes { ptr in
                sat_crc32(ptr.bindMemory(to: UInt8.self).baseAddress, decoded.count)
            }
            if actualCRC != expectedCRC {
                throw SatArchiveError.crcMismatch(safePath)
            }
            if result[safePath] != nil {
                throw SatArchiveError.invalidArchive("Duplicate entry '\(safePath)' in archive.")
            }
            result[safePath] = decoded
        }

        return ZipArchive(entries: result)
    }

    public func write(to url: URL) throws {
        let data = try encode()
        try data.write(to: url, options: .atomic)
    }

    public func encode() throws -> Data {
        var out = Data()
        struct CDRecord {
            var name: Data
            var crc: UInt32
            var compSize: UInt32
            var uncompSize: UInt32
            var method: UInt16
            var localOffset: UInt32
        }
        var cdRecords: [CDRecord] = []
        let sortedKeys = entries.keys.sorted()
        for path in sortedKeys {
            let safePath = try SatSecurityLimits.validateRelativePath(path)
            guard let raw = entries[path] else { continue }
            guard let nameBytes = safePath.data(using: .utf8) else {
                throw SatArchiveError.unsafePath(safePath)
            }
            let crc = raw.withUnsafeBytes { ptr in
                sat_crc32(ptr.bindMemory(to: UInt8.self).baseAddress, raw.count)
            }
            let ext = (safePath as NSString).pathExtension.lowercased()
            let skipDeflate = (ext == "png") || raw.count < 64
            var method: UInt16 = 0
            var storedPayload = raw
            if !skipDeflate {
                let defCap = raw.count + 64
                var defBuf = Data(count: defCap)
                let rawLen = raw.count
                var compLen = 0
                let rc = raw.withUnsafeBytes { srcPtr in
                    defBuf.withUnsafeMutableBytes { dstPtr in
                        sat_deflate_raw(
                            srcPtr.bindMemory(to: UInt8.self).baseAddress,
                            rawLen,
                            dstPtr.bindMemory(to: UInt8.self).baseAddress,
                            defCap,
                            &compLen
                        )
                    }
                }
                if rc == 0 && compLen < raw.count {
                    method = 8
                    storedPayload = defBuf.prefix(compLen)
                }
            }

            let localOff = UInt32(out.count)
            appendU32(&out, 0x0403_4b50)
            appendU16(&out, 20)
            appendU16(&out, 0x0800) // UTF-8
            appendU16(&out, method)
            appendU16(&out, 0)
            appendU16(&out, 0)
            appendU32(&out, crc)
            appendU32(&out, UInt32(storedPayload.count))
            appendU32(&out, UInt32(raw.count))
            appendU16(&out, UInt16(nameBytes.count))
            appendU16(&out, 0)
            out.append(nameBytes)
            out.append(storedPayload)

            cdRecords.append(CDRecord(
                name: nameBytes,
                crc: crc,
                compSize: UInt32(storedPayload.count),
                uncompSize: UInt32(raw.count),
                method: method,
                localOffset: localOff
            ))
        }

        let cdStart = UInt32(out.count)
        for rec in cdRecords {
            appendU32(&out, 0x0201_4b50)
            appendU16(&out, 0x031E)
            appendU16(&out, 20)
            appendU16(&out, 0x0800)
            appendU16(&out, rec.method)
            appendU16(&out, 0)
            appendU16(&out, 0)
            appendU32(&out, rec.crc)
            appendU32(&out, rec.compSize)
            appendU32(&out, rec.uncompSize)
            appendU16(&out, UInt16(rec.name.count))
            appendU16(&out, 0)
            appendU16(&out, 0)
            appendU16(&out, 0)
            appendU16(&out, 0)
            appendU32(&out, 0o100644 << 16)
            appendU32(&out, rec.localOffset)
            out.append(rec.name)
        }
        let cdSize = UInt32(out.count) - cdStart

        appendU32(&out, 0x0605_4b50)
        appendU16(&out, 0)
        appendU16(&out, 0)
        appendU16(&out, UInt16(cdRecords.count))
        appendU16(&out, UInt16(cdRecords.count))
        appendU32(&out, cdSize)
        appendU32(&out, cdStart)
        appendU16(&out, 0)
        return out
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func appendU16(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
    }

    private func appendU32(_ data: inout Data, _ v: UInt32) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 24) & 0xFF))
    }
}
