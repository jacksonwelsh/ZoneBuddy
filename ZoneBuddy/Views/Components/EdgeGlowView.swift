import SwiftUI

/// Full-screen edge glow effect that shows the rider's actual power zone color
/// around the screen edges. Sharp saturated color at the edge, tapering fast inward.
/// Shape follows the device's actual screen corner radius.
struct EdgeGlowView: View {
    let actualZone: PowerZone?
    let targetZone: PowerZone?
    let intensity: Double // 0…1

    private var glowColor: Color {
        actualZone?.color ?? .gray
    }

    private var isOnTarget: Bool {
        guard let actual = actualZone, let target = targetZone else { return false }
        return actual == target
    }

    private var edgeOpacity: Double {
        (isOnTarget ? 0.9 : 0.6) * intensity
    }

    /// How far the glow reaches inward (points).
    private var spread: CGFloat {
        isOnTarget ? 80 : 40
    }

    private var deviceCornerRadius: CGFloat { DeviceShape.screenCornerRadius }

    var body: some View {
        let cr = deviceCornerRadius

        ZStack {
            // Sharp edge border matching device corners — no blur
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .strokeBorder(
                    glowColor.opacity(edgeOpacity),
                    lineWidth: 4
                )

            // Inner glow: slightly inset, lightly blurred for fast taper
            RoundedRectangle(cornerRadius: cr - 4, style: .continuous)
                .strokeBorder(
                    glowColor.opacity(edgeOpacity * 0.6),
                    lineWidth: spread * 0.3
                )
                .blur(radius: spread * 0.2)

            // Wider soft glow layer for ambient effect
            RoundedRectangle(cornerRadius: cr - 8, style: .continuous)
                .strokeBorder(
                    glowColor.opacity(edgeOpacity * 0.2),
                    lineWidth: spread * 0.5
                )
                .blur(radius: spread * 0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.6), value: actualZone)
        .animation(.easeInOut(duration: 0.3), value: isOnTarget)
    }
}
