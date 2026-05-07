import SwiftUI

struct HeartRateZoneBar: View {
    let maxHR: Int
    let currentBPM: Int?
    var averageBPM: Int? = nil
    var compact: Bool = true
    var isPaused: Bool = false

    private var barHeight: CGFloat { compact ? 14 : 22 }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                            .fill(
                                LinearGradient(
                                    colors: isPaused
                                        ? [Color.gray.opacity(0.4), Color.gray.opacity(0.65)]
                                        : [fillColor.opacity(0.6), fillColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth, height: barHeight)
                            .animation(.smooth(duration: 0.3), value: bpm)
                    }

                    // Zone gap dividers (rendered on top so they cut through fill bar too)
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

            if let avg = averageBPM {
                HStack {
                    Text("Average \(avg) BPM")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                    Spacer()
                }
            }
        }
    }
}
