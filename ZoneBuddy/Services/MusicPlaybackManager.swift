import Foundation
import MusicKit

protocol MusicPlaybackManaging {
    func startPlayback(playlistID: String, kind: String?, shuffle: Bool, repeatMode: Bool, autoMix: Bool) async
    func pausePlayback()
    func resumePlayback()
    func stopPlayback()
    func skipToNext() async
    func skipToPrevious() async
}

final class MusicPlaybackManager: MusicPlaybackManaging {
    private let player = SystemMusicPlayer.shared

    func startPlayback(playlistID: String, kind: String?, shuffle: Bool, repeatMode: Bool, autoMix: Bool) async {
        if !SettingsManager.shared.playlistTakesOverMusic {
            let state = player.state
            if state.playbackStatus == .playing {
                return
            }
        }

        player.state.shuffleMode = shuffle ? .songs : .off
        player.state.repeatMode = repeatMode ? .all : MusicPlayer.RepeatMode.none

        do {
            let itemID = MusicItemID(rawValue: playlistID)

            if kind == MusicPickerKind.album.rawValue {
                var request = MusicLibraryRequest<Album>()
                request.filter(matching: \.id, equalTo: itemID)
                let response = try await request.response()
                guard let album = response.items.first else { return }
                player.queue = [album]
            } else {
                var request = MusicLibraryRequest<Playlist>()
                request.filter(matching: \.id, equalTo: itemID)
                let response = try await request.response()
                guard let playlist = response.items.first else { return }
                player.queue = [playlist]
            }

            try await player.play()
        } catch {
            print("Failed to start music playback: \(error)")
        }
    }

    func pausePlayback() {
        player.pause()
    }

    func resumePlayback() {
        Task {
            do {
                try await player.play()
            } catch {
                print("Failed to resume playback: \(error)")
            }
        }
    }

    func stopPlayback() {
        player.pause()
        player.queue = []
    }

    func skipToNext() async {
        do {
            try await player.skipToNextEntry()
        } catch {
            print("Failed to skip to next: \(error)")
        }
    }

    func skipToPrevious() async {
        do {
            try await player.skipToPreviousEntry()
        } catch {
            print("Failed to skip to previous: \(error)")
        }
    }
}
