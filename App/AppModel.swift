import Foundation
import SwiftUI
import AVFoundation
import os
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
    private static let log = Logger(subsystem: "org.duods.prototype", category: "app")
    // Every user-visible message is also logged so agents can diagnose without screenshots.
    @Published var message: String? {
        didSet { if let message { Self.log.error("\(message, privacy: .public)"); record("message", detail: message) } }
    }
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
        else { await diagnosticIfRequested() } // auto-launch only once foreground, so boot is not born paused
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
    /// `--selftest` (with `--diagnostic`): scripted P5 checks through the same session APIs the UI uses.
    /// Results are `selftest-*` events in session-events.jsonl; see docs/poc/WORK_LOG.md for interpretation.
    func runSelfTest() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
        guard let game = current else { record("selftest-abort", detail: "no game"); return }
        await wait(2); record("selftest-baseline")
        var held = DSInput(); held.buttons = 1 << UInt16(DSButton.a.rawValue)
        session.setInput(held); await wait(1); record("selftest-hold-a")
        session.releaseInputs(); await wait(1); record("selftest-release")
        session.toggleLid(); await wait(1); record("selftest-lid-closed")
        session.toggleLid(); await wait(1); record("selftest-lid-open")
        session.setInput(held)
        await pauseAndSave(reason: "selftest-pause")
        let pausedAt = session.stats.frames; await wait(1)
        record("selftest-paused-1s", detail: "frames_advanced=\(session.stats.frames - pausedAt)")
        foreground = true; await resume(); await wait(1); record("selftest-resumed")
        await close(); record("selftest-closed", detail: "current=\(current?.title ?? "nil")")
        await launch(game); await wait(2); record("selftest-relaunched")
        record("selftest-done")
    }
    func diagnosticIfRequested() async {
        guard !automaticLaunchDone else { return }; automaticLaunchDone = true
        guard ProcessInfo.processInfo.arguments.contains("--diagnostic"), let url = Bundle.main.url(forResource: "duo-diagnostic", withExtension: "nds") else { return }
        await importROM(url)
        if let game = games.first(where: { $0.title == "duo-diagnostic" }) {
            await launch(game)
            if ProcessInfo.processInfo.arguments.contains("--selftest") { await runSelfTest() }
        }
    }
    func recordGeometry(_ environment: DisplayEnvironment, _ solution: LayoutSolution) {
        func r(_ c: CGRect) -> String { String(format: "%.0f,%.0f %.0fx%.0f", c.minX, c.minY, c.width, c.height) }
        let regions = environment.reservedRegions.map { "\($0.kind):\(r($0.frame))" }.joined(separator: ";")
        record("geometry", detail: "bounds=\(r(environment.bounds)) safe=\(r(environment.safeBounds)) regions=[\(regions)] mode=\(solution.effectiveMode) compact=\(solution.isCompact) upper=\(r(solution.upperScreen)) lower=\(r(solution.lowerScreen))")
    }
    func record(_ event: String, detail: String? = nil) {
        let s = session.stats
        var fields: [String: Any] = ["event":event,"monotonic":ProcessInfo.processInfo.systemUptime,"phase":session.phase.rawValue,"frames":s.frames,"video_frames":s.video_frames,"audio_produced":s.audio_produced,"audio_consumed":s.audio_consumed,"audio_underruns":s.audio_underruns,"audio_overruns":s.audio_overruns,"core_fps":s.fps,"sample_rate":s.sample_rate,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"session":"single-process-owner"]
        if let detail { fields["detail"] = detail }
        if let frame = session.frame {
            // Evidence that real pixels reached the app: count non-black pixels per DS screen.
            var lit = [0, 0]; var sum = [[0, 0, 0], [0, 0, 0]] // per screen R,G,B
            frame.pixels.withUnsafeBytes { raw in
                let px = raw.bindMemory(to: UInt32.self)
                for i in 0..<min(px.count, 256 * 384) {
                    let v = px[i], s = i < 256 * 192 ? 0 : 1 // BGRA bytes -> little-endian 0xAARRGGBB
                    if v & 0x00FF_FFFF != 0 { lit[s] += 1 }
                    sum[s][0] += Int((v >> 16) & 0xFF); sum[s][1] += Int((v >> 8) & 0xFF); sum[s][2] += Int(v & 0xFF)
                }
            }
            fields["frame_sequence"] = frame.sequence; fields["lit_top"] = lit[0]; fields["lit_lower"] = lit[1]
            fields["mean_rgb_top"] = sum[0].map { $0 / (256 * 192) }; fields["mean_rgb_lower"] = sum[1].map { $0 / (256 * 192) }
        }
        guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: eventURL.path) { FileManager.default.createFile(atPath: eventURL.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: eventURL) { defer { try? file.close() }; do { try file.seekToEnd(); try file.write(contentsOf: data) } catch {} }
    }
}
