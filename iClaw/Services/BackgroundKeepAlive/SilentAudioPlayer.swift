import AVFoundation

/// Plays an inaudible audio track on loop to prevent iOS from suspending the app
/// in the background. Uses the `.playback` category with `.mixWithOthers` so it
/// does not interrupt the user's music or podcasts.
@MainActor
final class SilentAudioPlayer {

    private var audioPlayer: AVAudioPlayer?
    private(set) var isPlaying = false

    func start() {
        guard !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[SilentAudioPlayer] Failed to configure audio session: \(error)")
            return
        }

        guard let data = Self.generateSilentWAV() else {
            print("[SilentAudioPlayer] Failed to generate silent audio data")
            return
        }

        do {
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = -1 // loop forever
            player.volume = 0.01      // near-silent
            player.play()
            audioPlayer = player
            isPlaying = true
            print("[SilentAudioPlayer] Started silent playback")
        } catch {
            print("[SilentAudioPlayer] Failed to start playback: \(error)")
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[SilentAudioPlayer] Stopped")
    }

    // MARK: - WAV Generation

    /// Generates a minimal 1-second silent 16-bit mono WAV in memory.
    nonisolated static func generateSilentWAV() -> Data? {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = sampleRate   // 1 second
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let dataSize = numSamples * UInt32(bitsPerSample / 8) * UInt32(numChannels)
        let fileSize = 36 + dataSize

        var d = Data()
        d.reserveCapacity(Int(44 + dataSize))

        // RIFF header
        d.append(contentsOf: [UInt8]("RIFF".utf8))
        d.appendLE(fileSize)
        d.append(contentsOf: [UInt8]("WAVE".utf8))

        // fmt sub-chunk
        d.append(contentsOf: [UInt8]("fmt ".utf8))
        d.appendLE(UInt32(16))             // sub-chunk size
        d.appendLE(UInt16(1))              // PCM format
        d.appendLE(numChannels)
        d.appendLE(sampleRate)
        d.appendLE(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)) // byte rate
        d.appendLE(UInt16(numChannels * bitsPerSample / 8))                       // block align
        d.appendLE(bitsPerSample)

        // data sub-chunk
        d.append(contentsOf: [UInt8]("data".utf8))
        d.appendLE(dataSize)
        d.append(Data(count: Int(dataSize))) // all zeros = silence

        return d
    }
}

// MARK: - Data + Little-Endian Helpers

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
