import AVFoundation

protocol SpeechCueProviding {
    func speak(_ text: String)
    func stop()
}

final class LiveSpeechCueProvider: NSObject, SpeechCueProviding, AVSpeechSynthesizerDelegate {
    // Singleton to ensure consistent state and one-time initialization
    nonisolated(unsafe) private static let shared = LiveSpeechCueProvider()
    
    // Serial queue to prevent blocking the Main Thread with audio session IPC calls
    private let queue = DispatchQueue(label: "net.jacksonwelsh.ZoneBuddy.speech", qos: .userInitiated)
    
    // The synthesizer uses the shared audio session to support ducking
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Pre-warms the audio engine without interrupting background audio.
    /// MUST be called from `ZoneBuddyApp.init()`.
    static func warmUp() {
        // Dispatch to background to avoid any launch-time main thread blocking
        shared.queue.async {
            // 1. Initialize the synthesizer (loads dylibs)
            _ = shared.synthesizer
            
            // 2. Configure session to mix with others. 
            // This prevents the app from stopping music/podcasts when it launches.
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
                // Note: We do NOT setActive(true) here. That is what stops background audio if not careful.
            } catch {
                print("Failed to configure audio session in warmUp: \(error)")
            }
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        queue.async { [weak self] in
            guard let self else { return }
            
            let session = AVAudioSession.sharedInstance()
            do {
                // Ensure the category is set to duck others before we start speaking
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to activate audio session: \(error)")
            }
            
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queue.async {
            // Deactivate session to allow other audio to return to full volume
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
