import AVFoundation

protocol SpeechCueProviding {
    func speak(_ text: String)
    func stop()
}

final class LiveSpeechCueProvider: NSObject, SpeechCueProviding, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    override init() {
        self.voice = Self.preferredVoice()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        configureAudioSession()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let languageCode = AVSpeechSynthesisVoice.currentLanguageCode()
        let languagePrefix = String(languageCode.prefix(2))

        // Find all voices matching the user's language, preferring exact region match
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == languageCode || $0.language.hasPrefix(languagePrefix) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }

        // Return the highest-quality voice available, but only if better than the built-in default
        if let best = candidates.first, best.quality != .default {
            return best
        }
        return nil
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .duckOthers)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore — session may already be inactive
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.deactivateAudioSession()
        }
    }
}
