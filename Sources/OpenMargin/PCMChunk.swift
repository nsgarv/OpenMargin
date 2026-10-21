import AVFoundation
import Foundation

struct PCMChunk: Sendable {
    var sampleRate: Double
    var channelCount: Int
    var frameLength: Int
    var interleaved: [Float]
    var rms: Float

    init?(_ buffer: AVAudioPCMBuffer) {
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard channels > 0, frames > 0, let source = buffer.floatChannelData else { return nil }

        var samples: [Float] = []
        samples.reserveCapacity(frames * channels)
        var energy: Float = 0
        for frame in 0..<frames {
            for channel in 0..<channels {
                let sample = source[channel][frame]
                samples.append(sample)
                energy += sample * sample
            }
        }
        guard !samples.isEmpty else { return nil }
        sampleRate = buffer.format.sampleRate
        channelCount = channels
        frameLength = frames
        interleaved = samples
        let mean = energy / Float(samples.count)
        rms = mean.isFinite ? sqrt(max(mean, 0)) : 0
    }

    func makeBuffer() -> AVAudioPCMBuffer? {
        guard sampleRate > 0, channelCount > 0, frameLength > 0,
              interleaved.count >= frameLength * channelCount,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)),
              let destination = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameLength)
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                destination[channel][frame] = interleaved[frame * channelCount + channel]
            }
        }
        return buffer
    }
}

final class ChunkInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<PCMChunk>.Continuation?

    init(_ continuation: AsyncStream<PCMChunk>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ chunk: PCMChunk) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(chunk)
    }

    func finish() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}
