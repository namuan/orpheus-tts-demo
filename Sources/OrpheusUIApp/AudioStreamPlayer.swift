import Foundation
import AVFoundation

/// Bridges MLX audio buffers to the system sound card via AVAudioEngine.
/// Orpheus models natively sample at 24kHz Mono.
@MainActor
final class AudioStreamPlayer {
    static let shared = AudioStreamPlayer()

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let format: AVAudioFormat

    private init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("⚠️ AudioStreamPlayer: Failed to start engine: \(error.localizedDescription)")
        }
    }

    /// Schedule a PCM buffer for immediate playback. Starts the player node if needed.
    func playChunk(buffer: AVAudioPCMBuffer) {
        if !playerNode.isPlaying {
            playerNode.play()
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Stop playback and reset the player node.
    func stop() {
        playerNode.stop()
    }

    /// Restart the engine if it was stopped (e.g. after an interruption).
    func reset() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("⚠️ AudioStreamPlayer: Failed to restart engine: \(error.localizedDescription)")
            }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
