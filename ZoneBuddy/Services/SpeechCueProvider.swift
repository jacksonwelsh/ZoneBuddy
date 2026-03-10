import AVFoundation

protocol SpeechCueProviding {
    func speak(_ text: String)
    func stop()
    func startBackgroundKeepAlive()
    func stopBackgroundKeepAlive()
}

final class LiveSpeechCueProvider: NSObject, SpeechCueProviding, AVSpeechSynthesizerDelegate {
    // Singleton to ensure consistent state and one-time initialization
    private static let shared = LiveSpeechCueProvider()

    // Serial queue to prevent blocking the Main Thread with audio session IPC calls
    private let queue = DispatchQueue(label: "dev.jacksn.ZoneBuddy.speech", qos: .userInitiated)

    private let synthesizer = AVSpeechSynthesizer()
    private var silentPlayer: AVAudioPlayer?
    private var keepAliveActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Pre-warms the audio engine without interrupting background audio.
    /// MUST be called from `ZoneBuddyApp.init()`.
    static func warmUp() {
        shared.queue.async {
            _ = shared.synthesizer

            // Set initial category to mix with others. Prevents the first speak()
            // from transitioning away from .soloAmbient which would stop background music.
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            } catch {
                print("Failed to configure audio session in warmUp: \(error)")
            }
        }
    }

    // MARK: - Background Keep-Alive

    func startBackgroundKeepAlive() {
        queue.async { [weak self] in
            guard let self, !self.keepAliveActive else { return }
            self.keepAliveActive = true
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            self.startSilentPlayer()
        }
    }

    func stopBackgroundKeepAlive() {
        queue.async { [weak self] in
            guard let self else { return }
            self.keepAliveActive = false
            self.stopSilentPlayer()
        }
    }

    // MARK: - Speech

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        queue.async { [weak self] in
            guard let self else { return }

            // In iOS 16+, AVSpeechSynthesizer manages its own audio session internally.
            // Manual setCategory/setActive calls here can conflict with the synthesizer's
            // own session setup and silently suppress output. The silent player already
            // holds the background audio slot; just let the synthesizer speak on top.
            print("SpeechCueProvider: speaking '\(text)', isSpeaking=\(self.synthesizer.isSpeaking)")
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.restoreSessionAndKeepAlive()
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("SpeechCueProvider: utterance started")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("SpeechCueProvider: utterance finished")
        queue.async { [weak self] in
            self?.restoreSessionAndKeepAlive()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("SpeechCueProvider: utterance cancelled")
        queue.async { [weak self] in
            self?.restoreSessionAndKeepAlive()
        }
    }

    // MARK: - Private

    /// Restores the non-ducking audio category and restarts the silent player if needed.
    private func restoreSessionAndKeepAlive() {
        let session = AVAudioSession.sharedInstance()
        // Don't deactivate — that surrenders the background audio slot.
        // Category changes are allowed without deactivation since iOS 7.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        // Restart the silent player only if it stopped (e.g. first call before keep-alive started).
        if keepAliveActive && silentPlayer == nil {
            try? session.setActive(true)
            startSilentPlayer()
        }
    }

    private func startSilentPlayer() {
        guard silentPlayer == nil else { return }

        // 1 second of 16-bit mono silence at 8 kHz
        let sampleRate: UInt32 = 8_000
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let numSamples: UInt32 = sampleRate
        let dataSize = numSamples * UInt32(bitsPerSample / 8) * UInt32(numChannels)

        var wav = Data()
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wav.appendLittleEndian(UInt32(36 + dataSize))
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))                  // PCM
        wav.appendLittleEndian(numChannels)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8))
        wav.appendLittleEndian(UInt16(numChannels * bitsPerSample / 8))
        wav.appendLittleEndian(bitsPerSample)
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wav.appendLittleEndian(dataSize)
        wav.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        do {
            let player = try AVAudioPlayer(data: wav)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            silentPlayer = player
        } catch {
            print("SpeechCueProvider: failed to start silent player: \(error)")
        }
    }

    private func stopSilentPlayer() {
        silentPlayer?.stop()
        silentPlayer = nil
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
