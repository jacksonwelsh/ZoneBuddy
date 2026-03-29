import SwiftUI

/// Compact heart-rate zone bar for the Watch active-zone screen.
/// Always occupies the same vertical space so the surrounding layout
/// never shifts when HR data appears or disappears.
struct WatchHeartRateBarView: View {
    let currentBPM: Int?
    let maxHR: Int
    var showLabel: Bool = true

    private let barHeight: CGFloat = 10

    // MARK: - Helpers (mirrors HeartRateZoneBar logic)

    private func zoneSpans() -> [HeartRateZone: Double] {
        var spans: [HeartRateZone: Double] = [:]
        for zone in HeartRateZone.allCases {
            let range = zone.bpmRange(maxHR: maxHR)
            spans[zone] = max(Double(range.upperBound - range.lowerBound), 1)
        }
        return spans
    }

    private func fillFraction(_ bpm: Int) -> CGFloat {
        let spans = zoneSpans()
        let totalSpan = spans.values.reduce(0, +)
        var cumulativeSpan: Double = 0
        for zone in HeartRateZone.allCases {
            let range = zone.bpmRange(maxHR: maxHR)
            let span = spans[zone] ?? 1
            if bpm <= range.upperBound || zone == .zone5 {
                let frac = Double(bpm - range.lowerBound) / Double(max(range.upperBound - range.lowerBound, 1))
                let clampedFrac = min(max(frac, 0), 1)
                return CGFloat((cumulativeSpan + clampedFrac * span) / totalSpan)
            }
            cumulativeSpan += span
        }
        return 1.0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // BPM label above top-left of bar (optional — callers may render it elsewhere)
            if showLabel {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text(currentBPM.map { "\($0)" } ?? "--")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.white)
            }

            // Zone bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let spans = zoneSpans()
                let totalSpan = spans.values.reduce(0, +)

                ZStack(alignment: .leading) {
                    // Dark track
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: barHeight)

                    // Zone color tints
                    HStack(spacing: 0) {
                        ForEach(HeartRateZone.allCases) { zone in
                            let fraction = (spans[zone] ?? 1) / totalSpan
                            Rectangle()
                                .fill(zone.color.opacity(0.15))
                                .frame(width: CGFloat(fraction) * totalWidth, height: barHeight)
                        }
                    }
                    .clipShape(Capsule())

                    // Fill bar
                    if let bpm = currentBPM, maxHR > 0 {
                        let fraction = fillFraction(bpm)
                        let fillWidth = max(fraction * totalWidth, 0)
                        let hrZone = HeartRateZone.zone(forBPM: bpm, maxHR: maxHR)
                        let fillColor = hrZone?.color ?? Color.gray

                        Capsule()
                            .fill(LinearGradient(
                                colors: [fillColor.opacity(0.6), fillColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: fillWidth, height: barHeight)
                            .animation(.smooth(duration: 0.3), value: bpm)
                    }

                    // Zone gap dividers
                    HStack(spacing: 0) {
                        ForEach(HeartRateZone.allCases) { zone in
                            let fraction = (spans[zone] ?? 1) / totalSpan
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: CGFloat(fraction) * totalWidth, height: barHeight)
                                .overlay(alignment: .leading) {
                                    if zone != .zone1 {
                                        Rectangle()
                                            .fill(Color.black.opacity(0.5))
                                            .frame(width: 2)
                                    }
                                }
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: barHeight)
        }
    }
}
