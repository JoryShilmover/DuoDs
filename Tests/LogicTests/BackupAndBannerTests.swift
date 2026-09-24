// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import XCTest
@testable import DuoLogic

final class BackupAndBannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DuoBackupTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: Banner

    static func banner(title: String, paletteColor: UInt16 = 0x7C00) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x840)
        bytes[0] = 1
        // Every pixel uses palette index 1 except the top-left one (index 0, transparent).
        for i in 0x20..<0x220 { bytes[i] = 0x11 }
        bytes[0x20] = 0x10
        bytes[0x222] = UInt8(paletteColor & 0xFF); bytes[0x223] = UInt8(paletteColor >> 8)
        for (i, unit) in title.utf16.enumerated() where i < 128 {
            bytes[0x340 + i * 2] = UInt8(unit & 0xFF); bytes[0x341 + i * 2] = UInt8(unit >> 8)
        }
        return Data(bytes)
    }

    func testBannerParsesTitleLinesAndIcon() throws {
        let parsed = try XCTUnwrap(NDSBanner.parse(Self.banner(title: "Duo Quest\nChapter One\nHomebrew Co")))
        XCTAssertEqual(parsed.titleLines, ["Duo Quest", "Chapter One", "Homebrew Co"])
        XCTAssertEqual(parsed.title, "Duo Quest Chapter One")
        XCTAssertEqual(parsed.publisher, "Homebrew Co")
        XCTAssertEqual(parsed.iconRGBA.count, 32 * 32 * 4)
        XCTAssertEqual(Array(parsed.iconRGBA.prefix(8)), [0, 0, 0, 0, 0, 0, 255, 255]) // transparent, then blue (BGR555 0x7C00)
        XCTAssertNil(NDSBanner.parse(Data(count: 0x840))) // version 0 is not a banner
        XCTAssertNil(NDSBanner.parse(Data(count: 16)))
    }

    func testBannerReadsFromROMHeaderOffset() throws {
        var rom = Data(count: 0x200)
        rom[0x68] = 0x00; rom[0x69] = 0x02 // banner at 0x200
        rom.append(Self.banner(title: "Single Line"))
        let url = root.appendingPathComponent("game.nds")
        try rom.write(to: url)
        let parsed = try XCTUnwrap(NDSBanner.read(from: url))
        XCTAssertEqual(parsed.title, "Single Line")
        XCTAssertNil(parsed.publisher)
    }

    // MARK: ZIP and backup

    func testCRCAndZipRoundTripReadableByUnzip() throws {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
        let url = root.appendingPathComponent("test.zip")
        let writer = try ZipWriter(url: url)
        try writer.add("a/save.sav", data: Data(repeating: 7, count: 1000))
        try writer.add("manifest.json", data: Data("{}".utf8))
        try writer.finish()
        let files = try ZipReader.read(url: url)
        XCTAssertEqual(files["a/save.sav"], Data(repeating: 7, count: 1000))
        XCTAssertEqual(files["manifest.json"], Data("{}".utf8))
        #if os(macOS)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tq", url.path]
        unzip.standardOutput = FileHandle.nullDevice
        try unzip.run(); unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0, "system unzip rejects the archive")
        #endif
    }

    func testBackupRestoresSavesAndCompatibleStatesOnly() throws {
        let a = GameRecord(id: String(repeating: "a", count: 64), title: "Game: A/1")
        let b = GameRecord(id: String(repeating: "b", count: 64), title: "Game B")
        let source = PersistenceStore(root: root.appendingPathComponent("source"))
        try source.writeBattery(Data("save A".utf8), gameID: a.id)
        try source.saveState(Data("state A2".utf8), gameID: a.id, coreVersion: "v1", slot: .manual(2))
        try source.writeBattery(Data("save B".utf8), gameID: b.id)
        let url = root.appendingPathComponent("backup.zip")
        let exported = try SaveBackup.export(games: [a, b], persistence: source, coreVersion: "v1", to: url)
        XCTAssertEqual(exported.saves, 2); XCTAssertEqual(exported.states, 1)
        XCTAssertNotNil(try ZipReader.read(url: url)["Game_ A_1 [aaaaaaaa]/save.sav"])

        // A new install that has only game A, with an older save already present.
        let target = PersistenceStore(root: root.appendingPathComponent("target"))
        try target.writeBattery(Data("older A".utf8), gameID: a.id)
        var restored: [String] = []
        let summary = try SaveBackup.restore(from: url, games: [a], persistence: target, coreVersion: "v1") { restored.append($0.id) }
        XCTAssertEqual(summary.saves, 1); XCTAssertEqual(summary.states, 1)
        XCTAssertEqual(summary.missingGames, ["Game B"])
        XCTAssertEqual(restored, [a.id])
        XCTAssertEqual(try target.readBattery(gameID: a.id), Data("save A".utf8))
        XCTAssertEqual(try target.loadState(gameID: a.id, coreVersion: "v1", slot: .manual(2)), Data("state A2".utf8))

        // A different emulator build keeps the save but skips the states it cannot load.
        let other = PersistenceStore(root: root.appendingPathComponent("other"))
        let skipped = try SaveBackup.restore(from: url, games: [a, b], persistence: other, coreVersion: "v2")
        XCTAssertEqual(skipped.saves, 2); XCTAssertEqual(skipped.states, 0); XCTAssertEqual(skipped.incompatibleStates, 1)
    }

    func testRestoreRejectsNonBackups() throws {
        let notZip = root.appendingPathComponent("x.zip")
        try Data("hello".utf8).write(to: notZip)
        XCTAssertThrowsError(try SaveBackup.restore(from: notZip, games: [], persistence: PersistenceStore(root: root), coreVersion: "v1")) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        let noManifest = root.appendingPathComponent("y.zip")
        let writer = try ZipWriter(url: noManifest)
        try writer.add("other.txt", data: Data("x".utf8)); try writer.finish()
        XCTAssertThrowsError(try SaveBackup.restore(from: noManifest, games: [], persistence: PersistenceStore(root: root), coreVersion: "v1")) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
    }
}
