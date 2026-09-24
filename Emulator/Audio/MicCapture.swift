// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jory Shilmover
#if canImport(AVFoundation)
import AVFoundation
import Foundation

// Host microphone for the DS mic. Runs only while the user holds the on-screen Mic button, so the
// system mic indicator is visible exactly when capture happens. Constructed/stopped on the session
// executor; stop() completes before the core is destroyed (the tap captures the core pointer).
final class MicCapture {
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 1, interleaved: true)!

    func start(core: OpaquePointer) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: target) else {
            throw RuntimeError.audio("No microphone input is available")
        }
        let target = self.target
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / format.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            converter.convert(to: converted, error: nil) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if let samples = converted.int16ChannelData, converted.frameLength > 0 {
                duo_push_mic(core, samples[0], Int(converted.frameLength))
            }
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    deinit { stop() }
}
#endif
