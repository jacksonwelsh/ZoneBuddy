import SwiftUI

/// Glowing ring effect for the watch active zone screen.
/// Mirrors EdgeGlowView on iPhone/iPad but uses ContainerRelativeShape so the
/// glow follows the exact screen curvature of every watch model automatically —
/// no corner-radius arithmetic needed.
struct WatchEdgeGlowView: View {
    let zoneColor: Color

    var body: some View {
        let spread: CGFloat = 18

        ZStack {
            // Sharp edge border — tracks device screen shape exactly
            ContainerRelativeShape()
                .strokeBorder(zoneColor.opacity(0.9), lineWidth: 3)

            // Inner glow: slightly inset with gentle blur for fast taper
            ContainerRelativeShape()
                .inset(by: 3)
                .strokeBorder(zoneColor.opacity(0.55), lineWidth: spread * 0.35)
                .blur(radius: spread * 0.2)

            // Wider ambient layer for soft halo effect
            ContainerRelativeShape()
                .inset(by: 6)
                .strokeBorder(zoneColor.opacity(0.18), lineWidth: spread * 0.6)
                .blur(radius: spread * 0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: zoneColor)
    }
}
