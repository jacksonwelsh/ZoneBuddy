import Foundation
@testable import ZoneBuddy

final class MockMusicPlaybackManager: MusicPlaybackManaging {
    private(set) var startCalled = false
    private(set) var startPlaylistID: String?
    private(set) var startKind: String?
    private(set) var startShuffle: Bool?
    private(set) var startRepeatMode: Bool?
    private(set) var startAutoMix: Bool?

    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var stopCalled = false

    func startPlayback(playlistID: String, kind: String?, shuffle: Bool, repeatMode: Bool, autoMix: Bool) async {
        startCalled = true
        startPlaylistID = playlistID
        startKind = kind
        startShuffle = shuffle
        startRepeatMode = repeatMode
        startAutoMix = autoMix
    }

    func pausePlayback() {
        pauseCalled = true
    }

    func resumePlayback() {
        resumeCalled = true
    }

    func stopPlayback() {
        stopCalled = true
    }
}
