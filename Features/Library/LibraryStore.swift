// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation
import CryptoKit

public enum LibraryError: Error, Equatable {
    case invalidROM
    case ROMTooLarge
    case invalidGameID
    case missingGame
    case corruptMetadata
    case corruptROM
}

/// Owns imported ROMs. Callers must stop the active session before deleting its game.
public final class LibraryStore {
    public static let maximumROMSize = 512 * 1024 * 1024
    private let root: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.fileManager = .default
    }

    private var gamesRoot: URL { root.appendingPathComponent("Games", isDirectory: true) }

    public func importROM(from source: URL) throws -> GameRecord {
        lock.lock()
        defer { lock.unlock() }
        guard source.pathExtension.lowercased() == "nds" else { throw LibraryError.invalidROM }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LibraryError.invalidROM }
        if let size = values.fileSize, size > Self.maximumROMSize { throw LibraryError.ROMTooLarge }

        try verifyDirectoryIsNotLink(gamesRoot)
        try fileManager.createDirectory(at: gamesRoot, withIntermediateDirectories: true)
        let staging = gamesRoot.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: staging) }
        let stagedROM = staging.appendingPathComponent("game.nds")
        guard fileManager.createFile(atPath: stagedROM.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: stagedROM)
        defer { try? output.close() }
        var hash = SHA256()
        var count = 0
        var header = Data()
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            count += chunk.count
            guard count <= Self.maximumROMSize else { throw LibraryError.ROMTooLarge }
            hash.update(data: chunk)
            if header.count < 512 { header.append(chunk.prefix(512 - header.count)) }
            try output.write(contentsOf: chunk)
        }
        guard Self.validHeader(header, fileSize: count) else { throw LibraryError.invalidROM }
        try output.synchronize()
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let destination = gamesRoot.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            let existing = try readRecord(at: destination, expectedID: id)
            try verifyROM(at: destination.appendingPathComponent("game.nds"), expectedID: id)
            return existing
        }
        let filename = source.deletingPathExtension().lastPathComponent
        let rawTitle = String(String.UnicodeScalarView(filename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled Game" : String(rawTitle.prefix(120))
        let record = GameRecord(id: id, title: title)
        let metadata = try JSONEncoder().encode(record)
        try metadata.write(to: staging.appendingPathComponent("record.json"), options: .atomic)
        // A directory rename commits ROM and metadata together.
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            // A concurrent importer may have committed the same content first.
            if fileManager.fileExists(atPath: destination.path) {
                let existing = try readRecord(at: destination, expectedID: id)
                try verifyROM(at: destination.appendingPathComponent("game.nds"), expectedID: id)
                return existing
            }
            throw error
        }
        return record
    }

    public func list() throws -> [GameRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: gamesRoot.path) else { return [] }
        try verifyDirectoryIsNotLink(gamesRoot)
        let directories = try fileManager.contentsOfDirectory(at: gamesRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return try directories.compactMap { directory in
            guard Self.validID(directory.lastPathComponent) else { return nil }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return try readRecord(at: directory, expectedID: directory.lastPathComponent)
        }.sorted { $0.importedAt > $1.importedAt }
    }

    public func gameDirectory(for record: GameRecord) -> URL {
        let component = Self.validID(record.id) ? record.id : "invalid-\(Self.digest(Data(record.id.utf8)))"
        return gamesRoot.appendingPathComponent(component, isDirectory: true)
    }

    /// The cartridge's own icon and title; reads only the ROM header and banner (no hash check).
    public func banner(for record: GameRecord) -> NDSBanner? {
        guard Self.validID(record.id) else { return nil }
        return NDSBanner.read(from: gameDirectory(for: record).appendingPathComponent("game.nds"))
    }

    public func romURL(for record: GameRecord) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard Self.validID(record.id) else { throw LibraryError.invalidGameID }
        let directory = gameDirectory(for: record)
        guard try readRecord(at: directory, expectedID: record.id).id == record.id else { throw LibraryError.missingGame }
        let rom = directory.appendingPathComponent("game.nds")
        try verifyROM(at: rom, expectedID: record.id)
        return rom
    }

    public func delete(_ record: GameRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        guard Self.validID(record.id) else { throw LibraryError.invalidGameID }
        let directory = gameDirectory(for: record)
        _ = try readRecord(at: directory, expectedID: record.id)
        try fileManager.removeItem(at: directory)
    }

    private func readRecord(at directory: URL, expectedID: String) throws -> GameRecord {
        guard fileManager.fileExists(atPath: directory.path) else { throw LibraryError.missingGame }
        let metadataURL = directory.appendingPathComponent("record.json")
        let rom = directory.appendingPathComponent("game.nds")
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw LibraryError.corruptMetadata }
        let romValues = try rom.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard romValues.isRegularFile == true, romValues.isSymbolicLink != true else { throw LibraryError.corruptMetadata }
        let metadataValues = try metadataURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard metadataValues.isRegularFile == true, metadataValues.isSymbolicLink != true else { throw LibraryError.corruptMetadata }
        guard let data = try? Data(contentsOf: metadataURL),
              let record = try? JSONDecoder().decode(GameRecord.self, from: data),
              record.id == expectedID
        else { throw LibraryError.corruptMetadata }
        return record
    }

    private func verifyDirectoryIsNotLink(_ directory: URL) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: directory.path)) != nil { throw LibraryError.corruptMetadata }
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.corruptMetadata }
    }

    private func verifyROM(at url: URL, expectedID: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var length = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            length += chunk.count
            guard length <= Self.maximumROMSize else { throw LibraryError.corruptROM }
            hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedID else { throw LibraryError.corruptROM }
    }

    private static func validHeader(_ header: Data, fileSize: Int) -> Bool {
        guard header.count == 512 else { return false }
        func word(_ offset: Int) -> UInt64 {
            header[offset..<(offset + 4)].enumerated().reduce(0) { $0 | (UInt64($1.element) << (8 * $1.offset)) }
        }
        for (offsetField, sizeField) in [(0x20, 0x2C), (0x30, 0x3C)] {
            let offset = word(offsetField)
            let size = word(sizeField)
            guard offset >= 0x200, size > 0, offset <= UInt64(fileSize),
                  size <= UInt64(fileSize) - offset else { return false }
        }
        return true
    }

    private static func validID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
