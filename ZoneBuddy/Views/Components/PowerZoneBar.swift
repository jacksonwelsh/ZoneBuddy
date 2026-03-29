import SwiftUI

struct PowerZoneBar: View {
    let ftp: Int
    let targetZone: PowerZone?
    let currentPower: Int?
    var compact: Bool = true

    private var barHeight: CGFloat { compact ? 14 : 22 }

    /// Fraction through the full zone spectrum (0…1) for a given power.
    private func powerFraction(_ power: Int) -> CGFloat {
        let segments = PowerZone.allCases
        var cumulativeSpan: Double = 0
        let spans = zoneSpans()
        let total = spans.values.reduce(0, +)

        for zone in segments {
            let span = spans[zone] ?? 1
            let range = zone.wattRange(ftp: ftp)

            let effectiveLower: Int
            let effectiveUpper: Int
            switch zone {
            case .zone1:
                effectiveLower = 0
                effectiveUpper = range.upperBound
            case .zone7:
                effectiveLower = range.lowerBound
                effectiveUpper = range.lowerBound + Int(Double(ftp) * 0.30)
            default:
                effectiveLower = range.lowerBound
                effectiveUpper = range.upperBound
            }

            if power <= effectiveUpper || zone == .zone7 {
                let frac = Double(power - effectiveLower) / Double(max(effectiveUpper - effectiveLower, 1))
                let clampedFrac = min(max(frac, 0), 1)
                return CGFloat((cumulativeSpan + clampedFrac * span) / total)
            }
            cumulativeSpan += span
        }
        return 1.0
    }

    private func zoneSpans() -> [PowerZone: Double] {
        var spans: [PowerZone: Double] = [:]
        for zone in PowerZone.allCases {
            let range = zone.wattRange(ftp: ftp)
            let span: Double
            switch zone {
            case .zone1: span = Double(range.upperBound)
            case .zone7: span = Double(ftp) * 0.30
            default: span = Double(range.upperBound - range.lowerBound)
            }
            spans[zone] = max(span, 1)
        }
        return spans
    }

    /// Returns (xOffset, width) for a given zone within the bar.
    private func zoneRect(zone: PowerZone, totalWidth: CGFloat, spans: [PowerZone: Double], totalSpan: Double) -> (x: CGFloat, width: CGFloat) {
        var x: CGFloat = 0
        for z in PowerZone.allCases {
            let fraction = CGFloat((spans[z] ?? 1) / totalSpan)
            let w = fraction * totalWidth
            if z == zone {
                return (x, w)
            }
            x += w
        }
        return (x, 0)
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let spans = zoneSpans()
            let totalSpan = spans.values.reduce(0, +)
            let allZones = PowerZone.allCases
            let actualZone = currentPower.flatMap { PowerZone.zone(forPower: $0, ftp: ftp) }
            let isAboveTarget = actualZone != nil && targetZone != nil && actualZone!.rawValue > targetZone!.rawValue

            ZStack(alignment: .leading) {
                // Dark track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: barHeight)

                // Zone tick marks and target zone highlight
                HStack(spacing: 0) {
                    ForEach(Array(allZones.enumerated()), id: \.element) { index, zone in
                        let fraction = (spans[zone] ?? 1) / totalSpan
                        let segWidth = CGFloat(fraction) * totalWidth
                        let isTarget = zone == targetZone
                        let isFirst = index == 0
                        let isLast = index == allZones.count - 1
                        let cr = barHeight / 2

                        Rectangle()
                            .fill(isTarget ? zone.color.opacity(0.25) : .clear)
                            .frame(width: segWidth, height: barHeight)
                            .overlay {
                                if isTarget {
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: isFirst ? cr : 0,
                                        bottomLeadingRadius: isFirst ? cr : 0,
                                        bottomTrailingRadius: isLast ? cr : 0,
                                        topTrailingRadius: isLast ? cr : 0
                                    )
                                    .strokeBorder(zone.color.opacity(isAboveTarget ? 0.7 : 0.5), lineWidth: isAboveTarget ? 2 : 1.5)
                                    .padding(.leading, isFirst ? 0 : 1)
                                    .padding(.trailing, isLast ? 0 : 1)
                                }
                            }
                    }
                }
                .clipShape(Capsule())

                // Fill bar up to current power
                if let power = currentPower, ftp > 0 {
                    let fillFraction = powerFraction(power)
                    let fillWidth = max(fillFraction * totalWidth, 0)
                    let fillZone = PowerZone.zone(forPower: power, ftp: ftp)
                    let fillColor = fillZone?.color ?? Color.gray
                    let isInTarget = fillZone == targetZone && targetZone != nil

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.6), fillColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: barHeight)
                        .shadow(color: isInTarget ? fillColor.opacity(0.6) : .clear, radius: isInTarget ? 6 : 0)
                        .animation(.smooth(duration: 0.3), value: power)
                }

                // Zone gap dividers (rendered on top so they cut through fill bar too)
                HStack(spacing: 0) {
                    ForEach(Array(allZones.enumerated()), id: \.element) { index, zone in
                        let fraction = (spans[zone] ?? 1) / totalSpan
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: CGFloat(fraction) * totalWidth, height: barHeight)
                            .overlay(alignment: .leading) {
                                if index != 0 {
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
