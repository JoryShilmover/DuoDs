// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import Foundation
import CryptoKit

public enum PersistenceError: Error, Equatable {
    case invalidGameID
    case invalidCoreVersion
    case dataTooLarge
    case corruptData
    case incompatibleState
    case missingState
}

/// Stores cartridge data and one manual state per content hash.
/// The active core must be paused while these synchronous methods run.
public final class PersistenceStore {
    public static let maximumBatterySize = 64 * 1024 * 1024
    public static let maximumStateSize = 256 * 1024 * 1024
    private static let magic = Data("DUOSAVE1".utf8)
    private static let maximumHeaderSize = 4096

    private let root: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let beforeReplacement: (() throws -> Void)?

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.beforeReplacement = nil
    }

    // Deterministic interruption hook for host tests; production uses the public initializer.
    internal init(root: URL, beforeReplacement: @escaping () throws -> Void) {
        self.root = root.standardizedFileURL
        self.beforeReplacement = beforeReplacement
    }

    public func writeBattery(_ data: Data, gameID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard data.count <= Self.maximumBatterySize else { throw PersistenceError.dataTooLarge }
        let directory = try gameDirectory(gameID)
        try verifyDirectoryIsNotLink(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("battery.save")
        let backup = directory.appendingPathComponent("battery.previous")
        let encoded = try Self.encode(data, kind: .battery, gameID: gameID, coreVersion: nil)

        // Keep the last verified primary. A damaged primary never replaces a good backup.
        if fileManager.fileExists(atPath: primary.path),
           let previous = try? Self.readEnvelope(at: primary, kind: .battery, gameID: gameID, coreVersion: nil, maximumSize: Self.maximumBatterySize) {
            let verified = try Self.encode(previous, kind: .battery, gameID: gameID, coreVersion: nil)
            try verified.write(to: backup, options: .atomic)
        }
        try beforeReplacement?()
        try encoded.write(to: primary, options: .atomic)
    }

    public func readBattery(gameID: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        let directory = try gameDirectory(gameID)
        let primary = directory.appendingPathComponent("battery.save")
        let backup = directory.appendingPathComponent("battery.previous")
        if fileManager.fileExists(atPath: primary.path) {
            do {
                return try Self.readEnvelope(at: primary, kind: .battery, gameID: gameID, coreVersion: nil, maximumSize: Self.maximumBatterySize)
            } catch {
                guard fileManager.fileExists(atPath: backup.path) else { throw error }
                return try Self.readEnvelope(at: backup, kind: .battery, gameID: gameID, coreVersion: nil, maximumSize: Self.maximumBatterySize)
            }
        }
        if fileManager.fileExists(atPath: backup.path) {
            return try Self.readEnvelope(at: backup, kind: .battery, gameID: gameID, coreVersion: nil, maximumSize: Self.maximumBatterySize)
        }
        return nil
    }

    public func saveState(_ data: Data, gameID: String, coreVersion: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard data.count <= Self.maximumStateSize else { throw PersistenceError.dataTooLarge }
        try Self.validateCoreVersion(coreVersion)
        let directory = try gameDirectory(gameID).appendingPathComponent("States", isDirectory: true)
        try verifyDirectoryIsNotLink(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try Self.encode(data, kind: .state, gameID: gameID, coreVersion: coreVersion)
        try beforeReplacement?()
        try encoded.write(to: directory.appendingPathComponent("manual.state"), options: .atomic)
    }

    public func loadState(gameID: String, coreVersion: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        try Self.validateCoreVersion(coreVersion)
        let file = try gameDirectory(gameID).appendingPathComponent("States/manual.state")
        guard fileManager.fileExists(atPath: file.path) else { throw PersistenceError.missingState }
        return try Self.readEnvelope(at: file, kind: .state, gameID: gameID, coreVersion: coreVersion, maximumSize: Self.maximumStateSize)
    }

    private func gameDirectory(_ id: String) throws -> URL {
        guard id.utf8.count == 64,
              id.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) })
        else { throw PersistenceError.invalidGameID }
        let games = root.appendingPathComponent("Games", isDirectory: true)
        try verifyDirectoryIsNotLink(games)
        let directory = games.appendingPathComponent(id, isDirectory: true)
        try verifyDirectoryIsNotLink(directory)
        return directory
    }

    private func verifyDirectoryIsNotLink(_ directory: URL) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: directory.path)) != nil { throw PersistenceError.corruptData }
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw PersistenceError.corruptData }
    }

    private static func validateCoreVersion(_ version: String) throws {
        guard !version.isEmpty, version.utf8.count <= 128 else { throw PersistenceError.invalidCoreVersion }
    }

    private enum Kind: String, Codable { case battery, state }
    private struct Header: Codable {
        let format: Int
        let kind: Kind
        let gameID: String
        let coreVersion: String?
        let length: Int
        let sha256: String
    }

    private static func encode(_ payload: Data, kind: Kind, gameID: String, coreVersion: String?) throws -> Data {
        let header = Header(format: 1, kind: kind, gameID: gameID, coreVersion: coreVersion,
                            length: payload.count, sha256: digest(payload))
        let metadata = try JSONEncoder().encode(header)
        guard metadata.count <= maximumHeaderSize else { throw PersistenceError.corruptData }
        var output = Data(capacity: magic.count + 4 + metadata.count + payload.count)
        output.append(magic)
        var length = UInt32(metadata.count).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(metadata)
        output.append(payload)
        return output
    }

    private static func readEnvelope(at url: URL, kind: Kind, gameID: String, coreVersion: String?, maximumSize: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let fileSize = values.fileSize, fileSize <= maximumSize + maximumHeaderSize + 12
        else { throw PersistenceError.corruptData }
        let encoded = try Data(contentsOf: url)
        guard encoded.count >= magic.count + 4, encoded.prefix(magic.count) == magic else { throw PersistenceError.corruptData }
        let offset = magic.count
        let headerSize = encoded[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard headerSize > 0, headerSize <= maximumHeaderSize,
              encoded.count >= offset + 4 + Int(headerSize) else { throw PersistenceError.corruptData }
        let start = offset + 4
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: encoded[start..<(start + Int(headerSize))]) }
        catch { throw PersistenceError.corruptData }
        guard header.format == 1, header.kind == kind else { throw PersistenceError.corruptData }
        guard header.gameID == gameID else { throw PersistenceError.incompatibleState }
        if kind == .state && header.coreVersion != coreVersion { throw PersistenceError.incompatibleState }
        let payload = Data(encoded[(start + Int(headerSize))...])
        guard payload.count <= maximumSize, header.length == payload.count,
              header.sha256 == digest(payload) else { throw PersistenceError.corruptData }
        return payload
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
