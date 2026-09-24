import XCTest
import CryptoKit
@testable import DuoLogic

final class LibraryStoreTests: XCTestCase {
    private var root: URL!

    private func ROM(fill: UInt8) -> Data {
        var bytes = Data(repeating: fill, count: 0x240)
        func setWord(_ value: UInt32, at offset: Int) {
            for index in 0..<4 { bytes[offset + index] = UInt8((value >> (index * 8)) & 0xFF) }
        }
        setWord(0x200, at: 0x20) // ARM9 offset
        setWord(0x20, at: 0x2C) // ARM9 size
        setWord(0x220, at: 0x30) // ARM7 offset
        setWord(0x20, at: 0x3C) // ARM7 size
        return bytes
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DuoLibraryTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testImportDuplicateListAndDelete() throws {
        let source = root.appendingPathComponent("Example.nds")
        let bytes = ROM(fill: 0x42)
        try bytes.write(to: source)
        let store = LibraryStore(root: root.appendingPathComponent("Owned"))
        let first = try store.importROM(from: source)
        XCTAssertEqual(first.id, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try Data(contentsOf: store.romURL(for: first)), bytes)
        XCTAssertEqual(try store.importROM(from: source), first)
        XCTAssertEqual(try store.list(), [first])
        try store.delete(first)
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testInvalidInputsAndTraversalAreRejected() throws {
        let store = LibraryStore(root: root.appendingPathComponent("Owned"))
        let wrongExtension = root.appendingPathComponent("bad.bin")
        try Data(repeating: 1, count: 1024).write(to: wrongExtension)
        XCTAssertThrowsError(try store.importROM(from: wrongExtension))
        let shortROM = root.appendingPathComponent("short.nds")
        try Data(repeating: 1, count: 32).write(to: shortROM)
        XCTAssertThrowsError(try store.importROM(from: shortROM))
        let fake = GameRecord(id: "../../outside", title: "bad")
        XCTAssertThrowsError(try store.romURL(for: fake))
        XCTAssertThrowsError(try store.delete(fake))
        XCTAssertTrue(store.gameDirectory(for: fake).standardizedFileURL.path.hasPrefix(root.appendingPathComponent("Owned/Games").path))
    }

    func testDamagedMetadataDoesNotEraseROM() throws {
        let source = root.appendingPathComponent("Example.nds")
        try ROM(fill: 0x7F).write(to: source)
        let store = LibraryStore(root: root.appendingPathComponent("Owned"))
        let record = try store.importROM(from: source)
        let metadata = store.gameDirectory(for: record).appendingPathComponent("record.json")
        try Data("broken".utf8).write(to: metadata)
        XCTAssertThrowsError(try store.list())
        XCTAssertThrowsError(try store.delete(record))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.gameDirectory(for: record).appendingPathComponent("game.nds").path))
    }

    func testChangedOwnedROMDoesNotMasqueradeAsOriginalIdentity() throws {
        let source = root.appendingPathComponent("Example.nds")
        try ROM(fill: 0x20).write(to: source)
        let store = LibraryStore(root: root.appendingPathComponent("Owned"))
        let record = try store.importROM(from: source)
        let owned = store.gameDirectory(for: record).appendingPathComponent("game.nds")
        try ROM(fill: 0x21).write(to: owned)
        XCTAssertThrowsError(try store.romURL(for: record)) { error in
            XCTAssertEqual(error as? LibraryError, .corruptROM)
        }
        XCTAssertThrowsError(try store.importROM(from: source)) { error in
            XCTAssertEqual(error as? LibraryError, .corruptROM)
        }
    }

    func testGamesDirectoryLinkCannotRedirectImport() throws {
        let source = root.appendingPathComponent("Example.nds")
        try ROM(fill: 0x30).write(to: source)
        let owned = root.appendingPathComponent("Owned")
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: owned.appendingPathComponent("Games"), withDestinationURL: outside)
        XCTAssertThrowsError(try LibraryStore(root: owned).importROM(from: source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
