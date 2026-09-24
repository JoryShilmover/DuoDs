#if canImport(AVFoundation)
import AVFoundation
import Foundation

// Constructed and destroyed on the session executor. The render closure owns
// its scratch storage and only calls the lock-free native SPSC consumer.
final class AudioTransport {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchFrames = 4096

    init(core: OpaquePointer, sampleRate: Double) throws {
        guard sampleRate > 0, sampleRate.isFinite,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate, channels: 2, interleaved: false)
        else { throw RuntimeError.audio("Invalid core audio format") }
        scratch = .allocate(capacity: scratchFrames * 2)
        let scratch = self.scratch
        let chunkSize = scratchFrames
        source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var offset = 0
            while offset < Int(frameCount) {
                let count = min(chunkSize, Int(frameCount) - offset)
                _ = duo_read_audio(core, scratch, count)
                if buffers.count >= 2,
                   let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                   let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<count {
                        left[offset + i] = scratch[i * 2]
                        right[offset + i] = scratch[i * 2 + 1]
                    }
                } else if let interleaved = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
                    interleaved.advanced(by: offset * 2).update(from: scratch, count: count * 2)
                }
                offset += count
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        try engine.start()
    }

    var isRunning: Bool { engine.isRunning }

    // Called before duo_clear_audio or duo_destroy. AVAudioEngine.stop waits for
    // the render path to stop using the callback's captured core pointer.
    func stop() {
        engine.stop()
    }

    deinit {
        engine.stop()
        scratch.deallocate()
    }
}
#endif
