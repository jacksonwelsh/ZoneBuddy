import Foundation
@testable import ZoneBuddy

final class MockSpeechCueProvider: SpeechCueProviding {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCalled = false

    func speak(_ text: String) { spokenTexts.append(text) }
    func stop() { stopCalled = true }
    func startBackgroundKeepAlive() {}
    func stopBackgroundKeepAlive() {}
}
