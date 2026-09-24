import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let coreVersion = "bc4e4b67d2d470d7c682810a1e892cafd6f9082b+duo1"
    let session = EmulationSession.shared
    let root: URL
    let library: LibraryStore
    let persistence: PersistenceStore
    @Published var games: [GameRecord] = []
    @Published var current: GameRecord?
    @Published var message: String?
    @Published var busy = false
    @Published var owner: UUID?
    private var foreground = false
    private var interruption: NSObjectProtocol?
    private var routeChange: NSObjectProtocol?
    private var checkpoint: Timer?
    private var automaticLaunchDone = false
    private var eventURL: URL

    private init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DuoDS")
        library = LibraryStore(root: root)
        persistence = PersistenceStore(root: root)
        eventURL = root.appendingPathComponent("session-events.jsonl")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.pauseAndSave(reason: "audio-interruption") }
        }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.pauseAndSave(reason: "audio-route-change") }
        }
        checkpoint = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session.phase == .running, !self.busy else { return }
                await self.persistBattery()
                self.record("checkpoint")
            }
        }
    }

    func claim(_ scene: UUID) { if owner == nil { owner = scene } }
    func active(_ active: Bool, scene: UUID) async {
        claim(scene)
        guard owner == scene else { return }
        foreground = active
        if !active { await pauseAndSave(reason: "scene-inactive") }
        // Require explicit Resume after interruption; never silently capture input.
    }
    func reload() { do { games = try library.list() } catch { message = "Library: \(error.localizedDescription)" } }
    func importROM(_ url: URL) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let store = library
            _ = try await Task.detached { try store.importROM(from: url) }.value
            reload()
        } catch { message = "Import failed: \(error.localizedDescription)" }
    }
    func launch(_ game: GameRecord) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            if current?.id == game.id, session.phase == .paused {
                if foreground { try await session.resume() }; return
            }
            if current != nil {
                await session.pause()
                try await flushBattery()
                await session.stop()
            } else if session.phase == .failed { await session.stop() }
            current = game
            let directory = library.gameDirectory(for: game)
            try await session.boot(romURL: library.romURL(for: game), saveDirectory: directory.appendingPathComponent("CoreSaves"), systemDirectory: directory.appendingPathComponent("System"))
            if let battery = try persistence.readBattery(gameID: game.id) { try await session.restoreBattery(battery) }
            if foreground { try await session.resume() }
            record("boot")
        } catch {
            message = "Launch failed: \(error.localizedDescription)"
            await session.stop() // Do not save an uninitialized cartridge over existing progress.
            current = nil
        }
    }
    func pauseAndSave(reason: String) async {
        session.releaseInputs()
        await session.pause()
        await persistBattery()
        record(reason)
    }
    func resume() async {
        guard foreground, !busy else { return }
        do { try await session.resume(); record("resume") }
        catch { message = error.localizedDescription }
    }
    private func flushBattery() async throws {
        guard let game = current, session.phase != .idle, session.phase != .failed, session.phase != .loading else { return }
        if let data = try await session.snapshotBattery() { try persistence.writeBattery(data, gameID: game.id) }
    }
    func persistBattery() async {
        do { try await flushBattery() }
        catch { message = "Save failed; keep this session open: \(error.localizedDescription)" }
    }
    func close() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        await session.pause()
        do {
            try await flushBattery()
            await session.stop(); current = nil; record("stop")
        } catch { message = "Could not save. Session kept paused: \(error.localizedDescription)" }
    }
    func delete(_ game: GameRecord) {
        guard game.id != current?.id, !busy else { message = "Close the active game before deleting it."; return }
        do { try library.delete(game); reload() }
        catch { message = error.localizedDescription }
    }
    func state(save: Bool) async {
        guard let game = current, !busy else { return }
        busy = true; defer { busy = false }
        await session.pause()
        do {
            if save {
                let data = try await session.saveState()
                try persistence.saveState(data, gameID: game.id, coreVersion: Self.coreVersion)
            } else {
                let data = try persistence.loadState(gameID: game.id, coreVersion: Self.coreVersion)
                try await session.loadState(data)
            }
            message = save ? "Manual state saved. Persistent cartridge saves remain separate." : "Manual state restored. Tap Resume to continue."
            record(save ? "state-save" : "state-load")
        } catch { message = error.localizedDescription }
    }
    func diagnosticIfRequested() async {
        guard !automaticLaunchDone else { return }; automaticLaunchDone = true
        guard ProcessInfo.processInfo.arguments.contains("--diagnostic"), let url = Bundle.main.url(forResource: "duo-diagnostic", withExtension: "nds") else { return }
        await importROM(url)
        if let game = games.first(where: { $0.title == "duo-diagnostic" }) { await launch(game) }
    }
    func record(_ event: String) {
        let s = session.stats
        let fields: [String: Any] = ["event":event,"monotonic":ProcessInfo.processInfo.systemUptime,"phase":session.phase.rawValue,"frames":s.frames,"video_frames":s.video_frames,"audio_produced":s.audio_produced,"audio_consumed":s.audio_consumed,"audio_underruns":s.audio_underruns,"audio_overruns":s.audio_overruns,"core_fps":s.fps,"sample_rate":s.sample_rate,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"session":"single-process-owner"]
        guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: eventURL.path) { FileManager.default.createFile(atPath: eventURL.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: eventURL) { defer { try? file.close() }; do { try file.seekToEnd(); try file.write(contentsOf: data) } catch {} }
    }
}
