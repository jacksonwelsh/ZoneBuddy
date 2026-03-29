import SwiftUI

struct WatchTransitionBannerView: View {
    let upcomingLabel: String
    let upcomingColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
            Text(upcomingLabel)
                .font(.caption.weight(.semibold))
            Circle()
                .fill(upcomingColor)
                .frame(width: 10, height: 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
    }
}
