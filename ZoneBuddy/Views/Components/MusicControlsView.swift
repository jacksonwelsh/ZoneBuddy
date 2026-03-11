import SwiftUI
import MusicKit

struct MusicControlsView: View {
    let musicManager: MusicPlaybackManaging?
    let foregroundColor: Color
    let zoneColor: Color
    var compact: Bool = true

    private var buttonSize: CGFloat { compact ? 40 : 52 }
    private var iconSize: CGFloat { compact ? 16 : 20 }

    var body: some View {
        HStack(spacing: compact ? 16 : 24) {
            Button {
                guard let manager = musicManager else { return }
                Task { await manager.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(zoneColor.opacity(0.6), in: .circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                let player = SystemMusicPlayer.shared
                if player.state.playbackStatus == .playing {
                    player.pause()
                } else {
                    Task { try? await player.play() }
                }
            } label: {
                Image(systemName: SystemMusicPlayer.shared.state.playbackStatus == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(zoneColor.opacity(0.6), in: .circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Button {
                guard let manager = musicManager else { return }
                Task { await manager.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(zoneColor.opacity(0.6), in: .circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .disabled(musicManager == nil)
        .opacity(musicManager == nil ? 0.4 : 1.0)
    }
}
