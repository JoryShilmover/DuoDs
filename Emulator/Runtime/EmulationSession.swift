import Foundation
import Combine

public enum RuntimeError: LocalizedError {
    case unavailable(String)
    case core(String)
    case audio(String)
    case unsupportedState
    case invalidBatterySize(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let text), .core(let text), .audio(let text): return text
        case .unsupportedState: return "This game does not support core save states"
        case .invalidBatterySize(let expected, let got):
            return "Battery save is \(got) bytes; this cartridge expects \(expected)"
        }
    }
}

// One process-wide session. UI presentation can be recreated without touching
// the serial native owner or starting a second emulator.
@MainActor public final class EmulationSession: ObservableObject {
    public static let shared = EmulationSession()
    @Published public private(set) var phase: SessionPhase = .idle
    @Published public private(set) var frame: DSFrame?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var stats = DuoStats()
    public var microphoneAvailable: Bool { false }

    private let worker = RuntimeWorker()
    /// Resume awaits audio activation; a pause arriving meanwhile must not be dropped.
    private var resuming = false
    private var pauseAfterResume = false
    public var isResuming: Bool { resuming }
    /// Incremented whenever held input must be dropped; views cancel their own held state on change.
    @Published public private(set) var inputEpoch = 0
    private init() {
        let worker = self.worker
        worker.publish = { [weak self, weak worker] pixels, sequence, statistics in
            Task { @MainActor [weak self, weak worker] in
                defer { worker?.queue.async { worker?.framePending = false } }
                guard let self = self, self.phase == .running else { return }
                self.frame = DSFrame(pixels: pixels, sequence: sequence,
                                     timestamp: ProcessInfo.processInfo.systemUptime)
                self.stats = statistics
            }
        }
        worker.fail = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.errorMessage = message
                self?.phase = .failed
            }
        }
    }

    public func boot(romURL: URL, saveDirectory: URL, systemDirectory: URL) async throws {
        guard phase == .idle else { throw RuntimeError.unavailable("An emulation session is already active") }
        phase = .loading
        errorMessage = nil
        do {
            try await worker.perform {
                try self.worker.boot(rom: romURL.path, save: saveDirectory.path, system: systemDirectory.path)
            }
            phase = .paused // Caller may restore cartridge RAM before the first tick.
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func resume() async throws {
        guard phase == .paused, !resuming else { return }
        resuming = true; pauseAfterResume = false
        defer { resuming = false }
        do {
            try await worker.perform { try self.worker.resume() }
            // Stop/failure may have happened while awaiting; never resurrect those phases.
            guard phase == .paused else { return }
            if pauseAfterResume {
                try? await worker.perform { self.worker.pause() }
                return
            }
            phase = .running
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func pause() async {
        if resuming { pauseAfterResume = true; return }
        guard phase == .running else { return }
        phase = .paused
        try? await worker.perform { self.worker.pause() }
    }

    public func stop() async {
        if phase == .idle { return }
        phase = .stopping
        try? await worker.perform { self.worker.stop() }
        frame = nil
        stats = DuoStats()
        phase = .idle
    }

    public func setInput(_ input: DSInput) {
        let worker = worker
        worker.queue.async { worker.input = input }
    }

    public func releaseInputs() {
        setInput(DSInput())
        inputEpoch &+= 1
    }

    public func toggleLid() {
        let worker = worker
        worker.queue.async {
            if let core = worker.core { duo_toggle_lid(core) }
        }
    }

    public func snapshotBattery() async throws -> Data? {
        try await worker.perform { try self.worker.snapshotBattery() }
    }

    public func restoreBattery(_ data: Data) async throws {
        try await worker.perform { try self.worker.restoreBattery(data) }
    }

    public func saveState() async throws -> Data {
        try await worker.perform { try self.worker.saveState() }
    }

    public func loadState(_ data: Data) async throws {
        try await worker.perform { try self.worker.loadState(data) }
    }
}

// All fields except audio's native SPSC consumer are touched only on queue.
private final class RuntimeWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "org.duods.emulation", qos: .userInteractive)
    var core: OpaquePointer?
    var input = DSInput()
    var publish: ((Data, UInt64, DuoStats) -> Void)?
    var fail: ((String) -> Void)?
    private var generation: UInt64 = 0
    private var running = false
    private var deadline: UInt64 = 0
    private var period: UInt64 = 0
    private var lastPublishedSequence: UInt64 = 0
    var framePending = false
    private var audioDiscardedBaseline: UInt64 = 0
    #if canImport(AVFoundation)
    private var audio: AudioTransport?
    #endif

    func perform<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func boot(rom: String, save: String, system: String) throws {
        guard core == nil else { throw RuntimeError.unavailable("Emulator already loaded") }
        guard let instance = duo_create(system, save) else {
            throw RuntimeError.core("Could not create the emulator core")
        }
        core = instance
        guard duo_load(instance, rom) else {
            let text = String(cString: duo_error(instance))
            duo_destroy(instance)
            core = nil
            throw RuntimeError.core(text)
        }
        var currentStats = DuoStats()
        duo_stats(instance, &currentStats)
        guard currentStats.fps > 0, currentStats.fps.isFinite else {
            stop()
            throw RuntimeError.core("Core returned an invalid frame rate")
        }
        period = UInt64((1_000_000_000.0 / currentStats.fps).rounded())
        #if canImport(AVFoundation)
        do { audio = try AudioTransport(core: instance, sampleRate: currentStats.sample_rate) }
        catch { stop(); throw error }
        #endif
    }

    func resume() throws {
        guard let _ = core, !running else { return }
        #if canImport(AVFoundation)
        try audio?.start()
        #endif
        running = true
        generation &+= 1
        deadline = DispatchTime.now().uptimeNanoseconds
        schedule(generation)
    }

    func pause() {
        running = false
        generation &+= 1
        input = DSInput()
        #if canImport(AVFoundation)
        audio?.stop()
        #endif
        if let core = core { duo_clear_audio(core) }
        if let core = core {
            var stats = DuoStats()
            duo_stats(core, &stats)
            audioDiscardedBaseline = stats.audio_produced - stats.audio_consumed
        }
    }

    func stop() {
        pause()
        #if canImport(AVFoundation)
        audio = nil
        #endif
        if let core = core { duo_destroy(core) }
        core = nil
        lastPublishedSequence = 0
        audioDiscardedBaseline = 0
    }

    private func schedule(_ token: UInt64) {
        guard running, token == generation else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let delay = deadline > now ? deadline - now : 0
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(min(delay, UInt64(Int.max))))) {
            self.tick(token)
        }
    }

    private func tick(_ token: UInt64) {
        guard running, token == generation, let core = core else { return }
        var before = DuoStats()
        duo_stats(core, &before)
        // Limit queued audio to 120 ms; keeps control latency bounded when the
        // output route slows down. The core still advances from its AV rate.
        let cumulativeLead = before.audio_produced - before.audio_consumed
        let pendingAudio = cumulativeLead > audioDiscardedBaseline
            ? cumulativeLead - audioDiscardedBaseline : 0
        if before.sample_rate > 0,
           Double(pendingAudio) > before.sample_rate * 0.12 {
            deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000
            schedule(token)
            return
        }
        let native = DuoInput(buttons: input.buttons, touch_x: input.touchX,
                              touch_y: input.touchY, touching: input.touching)
        if !duo_run(core, native) {
            let message = String(cString: duo_error(core))
            pause()
            fail?(message)
            return
        }
        var count = 0
        var sequence: UInt64 = 0
        if let bytes = duo_frame(core, &count, &sequence), count == 256 * 384 * 4,
           sequence != lastPublishedSequence, !framePending {
            lastPublishedSequence = sequence
            framePending = true
            var statistics = DuoStats()
            duo_stats(core, &statistics)
            publish?(Data(bytes: bytes, count: count), sequence, statistics)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        deadline = deadline &+ period
        if now > deadline, now - deadline > period * 3 { deadline = now }
        schedule(token)
    }

    func snapshotBattery() throws -> Data? {
        guard let core = core else { throw RuntimeError.unavailable("No game is loaded") }
        let size = duo_save_size(core)
        if size == 0 { return nil }
        var data = Data(count: size)
        let success = data.withUnsafeMutableBytes { raw in
            duo_copy_save(core, raw.baseAddress, size)
        }
        if !success { throw RuntimeError.core("Could not copy cartridge save") }
        return data
    }

    func restoreBattery(_ data: Data) throws {
        guard let core = core else { throw RuntimeError.unavailable("No game is loaded") }
        let expected = duo_save_size(core)
        guard expected == data.count else {
            throw RuntimeError.invalidBatterySize(expected: expected, got: data.count)
        }
        let success = data.withUnsafeBytes { raw in
            duo_restore_save(core, raw.baseAddress, data.count)
        }
        if !success { throw RuntimeError.core("Could not restore cartridge save") }
    }

    func saveState() throws -> Data {
        guard let core = core else { throw RuntimeError.unavailable("No game is loaded") }
        let size = duo_state_size(core)
        guard size > 0 else { throw RuntimeError.unsupportedState }
        var data = Data(count: size)
        let success = data.withUnsafeMutableBytes { raw in
            duo_serialize(core, raw.baseAddress, size)
        }
        if !success { throw RuntimeError.core("The core could not serialize this game") }
        return data
    }

    func loadState(_ data: Data) throws {
        guard let core = core else { throw RuntimeError.unavailable("No game is loaded") }
        let size = duo_state_size(core)
        guard size > 0 else { throw RuntimeError.unsupportedState }
        guard data.count == size else { throw RuntimeError.core("Save state has the wrong size") }
        #if canImport(AVFoundation)
        let restartAudio = running
        if restartAudio { audio?.stop() }
        #endif
        let success = data.withUnsafeBytes { raw in
            duo_unserialize(core, raw.baseAddress, data.count)
        }
        if success {
            duo_clear_audio(core)
            var stats = DuoStats()
            duo_stats(core, &stats)
            audioDiscardedBaseline = stats.audio_produced - stats.audio_consumed
        }
        #if canImport(AVFoundation)
        if restartAudio {
            do { try audio?.start() }
            catch { pause(); throw error }
        }
        #endif
        if !success { throw RuntimeError.core("The core rejected this save state") }
    }
}
