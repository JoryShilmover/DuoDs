// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
import XCTest
@testable import DuoLogic

final class PersistenceStoreTests: XCTestCase {
    private let gameID = String(repeating: "a", count: 64)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DuoPersistenceTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBatteryRoundTripAndPreviousCopyRecovery() throws {
        let store = PersistenceStore(root: root)
        XCTAssertNil(try store.readBattery(gameID: gameID))
        let first = Data("old battery".utf8)
        let second = Data("new battery".utf8)
        try store.writeBattery(first, gameID: gameID)
        XCTAssertEqual(try store.readBattery(gameID: gameID), first)
        try store.writeBattery(second, gameID: gameID)
        XCTAssertEqual(try store.readBattery(gameID: gameID), second)
        let current = root.appendingPathComponent("Games/\(gameID)/battery.save")
        try Data("damaged".utf8).write(to: current)
        XCTAssertEqual(try store.readBattery(gameID: gameID), first)
        XCTAssertEqual(try Data(contentsOf: current), Data("damaged".utf8))
    }

    func testStateMismatchAndCorruptionPreserveBattery() throws {
        let store = PersistenceStore(root: root)
        let battery = Data("persistent progress".utf8)
        let state = Data(repeating: 0xA5, count: 32768)
        try store.writeBattery(battery, gameID: gameID)
        try store.saveState(state, gameID: gameID, coreVersion: "core-commit-1")
        XCTAssertEqual(try store.loadState(gameID: gameID, coreVersion: "core-commit-1"), state)
        XCTAssertThrowsError(try store.loadState(gameID: gameID, coreVersion: "core-commit-2")) { error in
            XCTAssertEqual(error as? PersistenceError, .incompatibleState)
        }
        let stateURL = root.appendingPathComponent("Games/\(gameID)/States/slot-1.state")
        let otherID = String(repeating: "b", count: 64)
        let otherState = root.appendingPathComponent("Games/\(otherID)/States/slot-1.state")
        try FileManager.default.createDirectory(at: otherState.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: stateURL, to: otherState)
        XCTAssertThrowsError(try store.loadState(gameID: otherID, coreVersion: "core-commit-1")) { error in
            XCTAssertEqual(error as? PersistenceError, .incompatibleState)
        }
        var bytes = try Data(contentsOf: stateURL)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: stateURL)
        XCTAssertThrowsError(try store.loadState(gameID: gameID, coreVersion: "core-commit-1")) { error in
            XCTAssertEqual(error as? PersistenceError, .corruptData)
        }
        XCTAssertEqual(try store.readBattery(gameID: gameID), battery)
    }

    func testInjectedReplacementFailureKeepsLastGoodFiles() throws {
        enum Injected: Error { case interruption }
        let normal = PersistenceStore(root: root)
        let battery = Data("old".utf8)
        let state = Data("old state".utf8)
        try normal.writeBattery(battery, gameID: gameID)
        try normal.saveState(state, gameID: gameID, coreVersion: "v1")
        let interrupted = PersistenceStore(root: root) { throw Injected.interruption }
        XCTAssertThrowsError(try interrupted.writeBattery(Data("new".utf8), gameID: gameID))
        XCTAssertThrowsError(try interrupted.saveState(Data("new state".utf8), gameID: gameID, coreVersion: "v1"))
        XCTAssertEqual(try normal.readBattery(gameID: gameID), battery)
        XCTAssertEqual(try normal.loadState(gameID: gameID, coreVersion: "v1"), state)
    }

    func testGameIDCannotEscapeOwnedDirectory() throws {
        let store = PersistenceStore(root: root)
        XCTAssertThrowsError(try store.writeBattery(Data(), gameID: "../outside"))
        XCTAssertThrowsError(try store.readBattery(gameID: "../outside"))
        XCTAssertThrowsError(try store.saveState(Data(), gameID: "../outside", coreVersion: "v1"))
        XCTAssertThrowsError(try store.loadState(gameID: "../outside", coreVersion: "v1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
    }

    func testGamesDirectoryLinkCannotRedirectSave() throws {
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Games"), withDestinationURL: outside)
        let store = PersistenceStore(root: root)
        XCTAssertThrowsError(try store.writeBattery(Data("secret".utf8), gameID: gameID))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testSlotsAreIndependentWithThumbnailsAndDelete() throws {
        let store = PersistenceStore(root: root)
        XCTAssertNil(store.stateInfo(gameID: gameID, slot: .manual(2)))
        try store.saveState(Data("two".utf8), gameID: gameID, coreVersion: "v1", slot: .manual(2), thumbnail: Data("png".utf8))
        try store.saveState(Data("auto".utf8), gameID: gameID, coreVersion: "v1", slot: .auto)
        XCTAssertEqual(try store.loadState(gameID: gameID, coreVersion: "v1", slot: .manual(2)), Data("two".utf8))
        XCTAssertEqual(try store.loadState(gameID: gameID, coreVersion: "v1", slot: .auto), Data("auto".utf8))
        XCTAssertThrowsError(try store.loadState(gameID: gameID, coreVersion: "v1", slot: .manual(1))) { error in
            XCTAssertEqual(error as? PersistenceError, .missingState)
        }
        XCTAssertEqual(store.stateInfo(gameID: gameID, slot: .manual(2))?.thumbnail, Data("png".utf8))
        XCTAssertNil(store.stateInfo(gameID: gameID, slot: .auto)?.thumbnail)
        try store.deleteState(gameID: gameID, slot: .auto)
        XCTAssertNil(store.stateInfo(gameID: gameID, slot: .auto))
        XCTAssertNotNil(store.stateInfo(gameID: gameID, slot: .manual(2)))
    }

    func testLegacySingleStateLoadsAsSlotOne() throws {
        let store = PersistenceStore(root: root)
        try store.saveState(Data("legacy".utf8), gameID: gameID, coreVersion: "v1")
        let states = root.appendingPathComponent("Games/\(gameID)/States")
        try FileManager.default.moveItem(at: states.appendingPathComponent("slot-1.state"), to: states.appendingPathComponent("manual.state"))
        XCTAssertEqual(try store.loadState(gameID: gameID, coreVersion: "v1", slot: .manual(1)), Data("legacy".utf8))
        XCTAssertNotNil(store.stateInfo(gameID: gameID, slot: .manual(1)))
        try store.saveState(Data("new".utf8), gameID: gameID, coreVersion: "v1", slot: .manual(1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: states.appendingPathComponent("manual.state").path))
        XCTAssertEqual(try store.loadState(gameID: gameID, coreVersion: "v1"), Data("new".utf8))
    }

    func testSaveImportFitting() {
        let save = Data((0..<512).map { UInt8($0 % 251) })
        XCTAssertEqual(SaveImport.fit(save, expectedSize: 512), save)
        var dsv = save
        dsv.append(Data(repeating: 0x20, count: 122 - 16))
        dsv.append(Data("|-DESMUME SAVE-|".utf8))
        XCTAssertEqual(SaveImport.fit(dsv, expectedSize: 512), save)
        XCTAssertEqual(SaveImport.fit(save + Data(repeating: 0xFF, count: 512), expectedSize: 512), save)
        XCTAssertNil(SaveImport.fit(save + Data([1]) + Data(repeating: 0xFF, count: 511), expectedSize: 512))
        XCTAssertNil(SaveImport.fit(save.prefix(256), expectedSize: 512))
        XCTAssertNil(SaveImport.fit(save, expectedSize: 0))
    }

    func testStagedImportIsTakenOnceAndLeavesSaveAlone() throws {
        let store = PersistenceStore(root: root)
        try store.writeBattery(Data("current".utf8), gameID: gameID)
        XCTAssertNil(try store.takeStagedBattery(gameID: gameID))
        try store.stageImportedBattery(Data("imported".utf8), gameID: gameID)
        XCTAssertTrue(store.hasStagedBattery(gameID: gameID))
        XCTAssertEqual(try store.readBattery(gameID: gameID), Data("current".utf8))
        XCTAssertEqual(try store.takeStagedBattery(gameID: gameID), Data("imported".utf8))
        XCTAssertFalse(store.hasStagedBattery(gameID: gameID))
        XCTAssertNil(try store.takeStagedBattery(gameID: gameID))
    }
}
