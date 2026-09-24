import Foundation
import SwiftUI
import AVFoundation
import os
import UIKit
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.pauseAndSave(reason: "audio-interruption") }
        }
        session.onTouchConsumed = { [weak self] latency in
            self?.record("touch-consumed", detail: String(format: "latency_ms=%.1f", latency * 1000))
        }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            // Pause only when output disappears (e.g. headphones unplugged); the app's own category/activation changes also post this.
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable else { return }
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
    /// A closed window gives up the session so a new window is not locked out (P8 review).
    func release(_ scene: UUID) async {
        guard owner == scene else { return }
        await pauseAndSave(reason: "scene-disconnected")
        owner = nil
    }
    /// Moves the single session to another window; it stays paused until the user resumes there.
    func takeOver(_ scene: UUID) async {
        guard owner != scene else { return }
        await pauseAndSave(reason: "scene-handoff")
        owner = scene
        foreground = true
    }
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
        guard !busy else { record("import-skipped", detail: "busy"); return }
        busy = true; defer { busy = false }
        do {
            let store = library
            _ = try await Task.detached { try store.importROM(from: url) }.value
            reload()
        } catch { message = "Import failed: \(error.localizedDescription)" }
    }
    func launch(_ game: GameRecord) async {
        guard !busy else { record("launch-skipped", detail: "busy"); return }
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
            PresentationStats.shared.reset()
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
        guard let game = current, session.phase != .idle, session.phase != .loading else { return }
        // After a runtime failure the core is paused but still loaded: flush once so recent in-game saves
        // are not lost. PersistenceStore keeps the previous save as `battery.previous` for recovery.
        if session.phase == .failed { record("failed-core-flush") }
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
        // Reviewer finding: a pause arriving while resume is still activating audio must win.
        let racing = Task { try? await session.resume() }
        while !session.isResuming { await Task.yield() } // pause must land while resume is in flight
        await session.pause(); await racing.value
        let before = session.stats.frames; await wait(1)
        record("selftest-pause-during-resume", detail: "phase=\(session.phase.rawValue) frames_advanced=\(session.stats.frames - before)")
        foreground = true; await resume(); await wait(1); record("selftest-resumed")
        await close(); record("selftest-closed", detail: "current=\(current?.title ?? "nil")")
        await launch(game); await wait(2); record("selftest-relaunched")
        record("selftest-done")
    }
    /// `--selftest-states` (V20): save a manual state, let the game run, restore, and compare frames.
    /// A real restore makes the post-restore frame much closer to the saved frame than the advanced one.
    /// On content without serialization support it records the explicit "unavailable" outcome instead.
    func runStateSelfTest() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
        func difference(_ a: Data?, _ b: Data?) -> Double {
            guard let a, let b, a.count == b.count, !a.isEmpty else { return -1 }
            var total = 0, samples = 0
            a.withUnsafeBytes { x in b.withUnsafeBytes { y in
                // Odd stride so B, G, R and A all get sampled (a stride of 16 only ever read blue).
                for i in stride(from: 0, to: a.count, by: 7) { total += abs(Int(x[i]) - Int(y[i])); samples += 1 }
            } }
            return Double(total) / Double(max(samples, 1))
        }
        guard current != nil else { record("states-abort", detail: "no game"); return }
        await wait(4)
        let savedFrame = session.frame?.pixels
        message = nil
        await state(save: true)
        let saveOutcome = message ?? ""
        message = nil
        guard saveOutcome.hasPrefix("Manual state saved") else {
            record("states-unavailable", detail: saveOutcome)
            await resume(); return
        }
        record("states-saved")
        await resume(); await wait(3)
        let advancedFrame = session.frame?.pixels
        await state(save: false)
        let loadOutcome = message ?? ""
        message = nil
        await resume(); await wait(0.25)
        let restoredFrame = session.frame?.pixels
        let advanced = difference(savedFrame, advancedFrame), restored = difference(savedFrame, restoredFrame)
        record("states-roundtrip", detail: "load=\(loadOutcome.prefix(24)) diff_saved_vs_advanced=\(String(format: "%.2f", advanced)) diff_saved_vs_restored=\(String(format: "%.2f", restored)) restored_closer=\(restored >= 0 && restored < advanced)")
    }
    /// `--selftest-mic` (V15): hold the Mic control for 2 s. `mic_pushed` counts captured samples,
    /// `mic_consumed` samples the emulated DS read. With permission denied both stay 0 (silence).
    func runMicSelfTest() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
        await wait(2); record("mic-selftest-before")
        await microphone(held: true); await wait(2); record("mic-selftest-held")
        await microphone(held: false); await wait(1); record("mic-selftest-released")
    }
    func diagnosticIfRequested() async {
        guard !automaticLaunchDone else { return }; automaticLaunchDone = true
        let arguments = ProcessInfo.processInfo.arguments
        record("auto-launch", detail: arguments.dropFirst().joined(separator: " "))
        // `--launch-game <id prefix>`: open an already-imported library game (content never leaves the device).
        if let index = arguments.firstIndex(of: "--launch-game"), index + 1 < arguments.count,
           let game = games.first(where: { $0.id.hasPrefix(arguments[index + 1]) }) {
            await launch(game)
            if arguments.contains("--selftest-states") { await runStateSelfTest() }
            return
        }
        if arguments.contains("--launch-game") { record("auto-launch-failed", detail: "no library game matches"); return }
        guard arguments.contains("--diagnostic"), let url = Bundle.main.url(forResource: "duo-diagnostic", withExtension: "nds") else { return }
        await importROM(url)
        if let game = games.first(where: { $0.title == "duo-diagnostic" }) {
            await launch(game)
            if arguments.contains("--selftest") { await runSelfTest() }
            if arguments.contains("--selftest-states") { await runStateSelfTest() }
            if arguments.contains("--selftest-mic") { await runMicSelfTest() }
        }
    }
    /// V15: hold-to-talk. Permission is requested on first use (never at launch); if denied the game
    /// hears silence and the user is told once where to enable it.
    private var micDeniedNoticeShown = false
    func microphone(held: Bool) async {
        guard held else { session.setMicrophone(held: false); record("mic-release"); return }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            session.setMicrophone(held: true); record("mic-hold")
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            record("mic-permission", detail: granted ? "granted" : "denied")
            if !granted { micDeniedNoticeShown = true; message = "Microphone access was not allowed. The game will hear silence; you can enable it in Settings → Privacy & Security → Microphone." }
        default:
            record("mic-denied")
            if !micDeniedNoticeShown {
                micDeniedNoticeShown = true
                message = "Microphone access is off for Duo DS, so the game hears silence. Enable it in Settings → Privacy & Security → Microphone."
            }
        }
    }
    /// V10: log the raw contact and its DS mapping, so accuracy can be recomputed independently,
    /// then time when the core consumes it.
    func recordStylus(_ point: CGPoint, lowerScreen: CGRect, uptime: Double) {
        let mapped = InputRouter.mapTouch(point, in: lowerScreen)
        record("touch-down", detail: String(format: "view=%.2f,%.2f rect=%.2f,%.2f,%.2f,%.2f ds=%d,%d event_uptime=%.4f",
            point.x, point.y, lowerScreen.minX, lowerScreen.minY, lowerScreen.width, lowerScreen.height,
            Int(mapped?.x ?? 999), Int(mapped?.y ?? 999), uptime))
        session.markTouch(uptime: uptime)
    }
    func recordGeometry(_ environment: DisplayEnvironment, _ solution: LayoutSolution) {
        func r(_ c: CGRect) -> String { String(format: "%.0f,%.0f %.0fx%.0f", c.minX, c.minY, c.width, c.height) }
        let regions = environment.reservedRegions.map { "\($0.kind):\(r($0.frame))" }.joined(separator: ";")
        record("geometry", detail: "bounds=\(r(environment.bounds)) safe=\(r(environment.safeBounds)) regions=[\(regions)] mode=\(solution.effectiveMode) compact=\(solution.isCompact) upper=\(r(solution.upperScreen)) lower=\(r(solution.lowerScreen))")
    }
    func record(_ event: String, detail: String? = nil) {
        let s = session.stats
        var fields: [String: Any] = ["event":event,"monotonic":ProcessInfo.processInfo.systemUptime,"phase":session.phase.rawValue,"frames":s.frames,"video_frames":s.video_frames,"audio_produced":s.audio_produced,"audio_consumed":s.audio_consumed,"audio_underruns":s.audio_underruns,"audio_overruns":s.audio_overruns,"mic_pushed":s.mic_pushed,"mic_consumed":s.mic_consumed,"audio_buffered_ms":s.sample_rate > 0 ? Int(Double(s.audio_buffered) * 1000 / s.sample_rate) : 0,"core_fps":s.fps,"sample_rate":s.sample_rate,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"session":"single-process-owner"]
        if let detail { fields["detail"] = detail }
        if let current { fields["game"] = String(current.id.prefix(12)) } // hash prefix only, never the title
        // V12 conditions: battery, low power, brightness (thermal state above).
        let device = UIDevice.current
        fields["battery_level"] = device.batteryLevel
        fields["battery_state"] = device.batteryState.rawValue
        fields["low_power_mode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        fields["brightness"] = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness ?? -1
        // V09: presentation counters since boot (compare `presented_unique` with `video_frames`).
        let shown = PresentationStats.shared
        fields["presented_unique"] = shown.unique
        fields["presented_repeated"] = shown.repeated
        fields["presented_skipped"] = shown.skipped
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
