import SwiftUI

/// Glowing ring effect for the watch active zone screen.
/// Mirrors EdgeGlowView on iPhone/iPad — same three-layer approach, scaled for the
/// smaller display. Corner radius is derived from the view's actual rendered width
/// via GeometryReader rather than WKInterfaceDevice, so it stays accurate even if
/// the rendered frame differs from the logical screen bounds.
struct WatchEdgeGlowView: View {
    let zoneColor: Color

    var body: some View {
        let spread: CGFloat = 18

        GeometryReader { geo in
            // Apple Watch displays have noticeably rounded corners; ~30% of screen
            // width gives a good match across all models (≈49 pt on 40 mm up to
            // ≈62 pt on Ultra). Adjust this constant if a specific model still clips.
            let cr = geo.size.width * 0.29

            ZStack {
                // Sharp edge border — no blur, matches device corners exactly
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .strokeBorder(zoneColor.opacity(0.9), lineWidth: 3)

                // Inner glow: slightly inset with gentle blur for fast taper
                RoundedRectangle(cornerRadius: max(1, cr - 3), style: .continuous)
                    .strokeBorder(zoneColor.opacity(0.55), lineWidth: spread * 0.35)
                    .blur(radius: spread * 0.2)

                // Wider ambient layer for soft halo effect
                RoundedRectangle(cornerRadius: max(1, cr - 6), style: .continuous)
                    .strokeBorder(zoneColor.opacity(0.18), lineWidth: spread * 0.6)
                    .blur(radius: spread * 0.4)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: zoneColor)
    }
}
