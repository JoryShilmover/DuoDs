// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation

public enum BackupError: Error, Equatable {
    case notABackup
    case unsupportedArchive
    case corruptArchive
}

/// A backup of every game's cartridge save and manual save states, as an uncompressed ZIP: it opens in
/// Files, and each `save.sav` is a raw cartridge save other emulators can use. ROMs are never included.
public enum SaveBackup {
    public struct Summary: Equatable, Sendable {
        public var saves = 0, states = 0
        /// Games in the backup that are not in this library (import the game, then restore again).
        public var missingGames: [String] = []
        /// States made by a different emulator build, which this build cannot load.
        public var incompatibleStates = 0
    }

    struct Manifest: Codable {
        struct Game: Codable {
            let id: String
            let title: String
            let save: String?
            let states: [State]
        }
        struct State: Codable {
            let slot: Int
            let path: String
            let coreVersion: String
        }
        let format: Int
        let created: Date
        let games: [Game]
    }

    private static let manifestPath = "manifest.json"

    /// Writes the backup to `url`. Returns what it contains.
    @discardableResult
    public static func export(games: [GameRecord], persistence: PersistenceStore, coreVersion: String, to url: URL) throws -> Summary {
        let writer = try ZipWriter(url: url)
        var summary = Summary()
        var entries: [Manifest.Game] = []
        for game in games {
            let folder = folderName(for: game)
            var savePath: String?
            if let save = try? persistence.readBattery(gameID: game.id) {
                savePath = folder + "/save.sav"
                try writer.add(savePath!, data: save)
                summary.saves += 1
            }
            var states: [Manifest.State] = []
            for case .manual(let n) in StateSlot.manualSlots {
                guard let data = try? persistence.loadState(gameID: game.id, coreVersion: coreVersion, slot: .manual(n)) else { continue }
                let path = folder + "/state-\(n).state"
                try writer.add(path, data: data)
                states.append(.init(slot: n, path: path, coreVersion: coreVersion))
                summary.states += 1
            }
            if savePath != nil || !states.isEmpty {
                entries.append(.init(id: game.id, title: game.title, save: savePath, states: states))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try writer.add(manifestPath, data: encoder.encode(Manifest(format: 1, created: Date(), games: entries)))
        try writer.finish()
        return summary
    }

    /// Restores saves and states for games that are in `games`. A restored cartridge save goes through
    /// `writeBattery`, so the save it replaces is kept as the previous copy. `restoredSave` is called for
    /// each game whose save was restored (the caller drops its stale automatic state).
    public static func restore(from url: URL, games: [GameRecord], persistence: PersistenceStore, coreVersion: String,
                               restoredSave: (GameRecord) -> Void = { _ in }) throws -> Summary {
        let files = try ZipReader.read(url: url)
        guard let manifestData = files[manifestPath] else { throw BackupError.notABackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData), manifest.format == 1 else { throw BackupError.notABackup }
        var summary = Summary()
        for entry in manifest.games {
            guard let game = games.first(where: { $0.id == entry.id }) else { summary.missingGames.append(entry.title); continue }
            if let path = entry.save {
                guard let data = files[path] else { throw BackupError.corruptArchive }
                try persistence.writeBattery(data, gameID: game.id)
                restoredSave(game)
                summary.saves += 1
            }
            for state in entry.states where StateSlot.manualSlots.contains(.manual(state.slot)) {
                guard state.coreVersion == coreVersion else { summary.incompatibleStates += 1; continue }
                guard let data = files[state.path] else { throw BackupError.corruptArchive }
                try persistence.saveState(data, gameID: game.id, coreVersion: coreVersion, slot: .manual(state.slot))
                summary.states += 1
            }
        }
        return summary
    }

    static func folderName(for game: GameRecord) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_.,'()&!"))
        let clean = String(String.UnicodeScalarView(game.title.unicodeScalars.map { allowed.contains($0) ? $0 : "_" }))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return "\(clean.isEmpty ? "Game" : String(clean.prefix(60))) [\(game.id.prefix(8))]"
    }
}

// MARK: - Minimal ZIP (stored entries only)

final class ZipWriter {
    private let handle: FileHandle
    private var central = Data()
    private var count = 0
    private var offset: UInt64 = 0

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
    }

    func add(_ path: String, data: Data) throws {
        let name = Data(path.utf8)
        guard data.count < UInt32.max, offset < UInt32.max, name.count < UInt16.max else { throw BackupError.unsupportedArchive }
        let crc = CRC32.checksum(data)
        let (time, date) = Self.dosTimestamp(Date())
        var local = Data()
        local.le32(0x04034b50); local.le16(20); local.le16(0x0800) // version 2.0, UTF-8 names
        local.le16(0); local.le16(time); local.le16(date)
        local.le32(crc); local.le32(UInt32(data.count)); local.le32(UInt32(data.count))
        local.le16(UInt16(name.count)); local.le16(0); local.append(name)
        try handle.write(contentsOf: local)
        try handle.write(contentsOf: data)

        central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800)
        central.le16(0); central.le16(time); central.le16(date)
        central.le32(crc); central.le32(UInt32(data.count)); central.le32(UInt32(data.count))
        central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
        central.le32(0); central.le32(UInt32(offset)); central.append(name)
        offset += UInt64(local.count + data.count)
        count += 1
    }

    func finish() throws {
        guard count < UInt16.max, offset < UInt32.max else { throw BackupError.unsupportedArchive }
        var end = Data()
        end.le32(0x06054b50); end.le16(0); end.le16(0); end.le16(UInt16(count)); end.le16(UInt16(count))
        end.le32(UInt32(central.count)); end.le32(UInt32(offset)); end.le16(0)
        try handle.write(contentsOf: central)
        try handle.write(contentsOf: end)
        try handle.close()
    }

    static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

enum ZipReader {
    /// Reads every stored entry. Compressed archives (e.g. re-zipped by another tool) are rejected.
    static func read(url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        var files: [String: Data] = [:]
        var p = 0
        func need(_ n: Int) throws { guard p + n <= data.count else { throw BackupError.corruptArchive } }
        while true {
            try need(4)
            let signature = data.littleEndianUInt32(at: p)
            if signature == 0x02014b50 || signature == 0x06054b50 { break } // central directory: all entries read
            guard signature == 0x04034b50 else { throw files.isEmpty ? BackupError.notABackup : BackupError.corruptArchive }
            try need(30)
            let flags = data.le16(at: p + 6), method = data.le16(at: p + 8)
            let crc = data.littleEndianUInt32(at: p + 14)
            let size = Int(data.littleEndianUInt32(at: p + 18)), stored = Int(data.littleEndianUInt32(at: p + 22))
            let nameLength = Int(data.le16(at: p + 26)), extraLength = Int(data.le16(at: p + 28))
            guard method == 0, flags & 0x0008 == 0, size == stored else { throw BackupError.unsupportedArchive }
            p += 30
            try need(nameLength + extraLength + size)
            let name = String(decoding: data[(data.startIndex + p)..<(data.startIndex + p + nameLength)], as: UTF8.self)
            p += nameLength + extraLength
            let body = Data(data[(data.startIndex + p)..<(data.startIndex + p + size)])
            guard CRC32.checksum(body) == crc else { throw BackupError.corruptArchive }
            files[name] = body
            p += size
        }
        return files
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        (0..<8).reduce(UInt32(i)) { c, _ in c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for i in 0..<4 { append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    func le16(at offset: Int) -> UInt16 { UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8 }
}
