import SwiftUI

struct NextIntervalTile: View {
    let nextZone: PowerZone?
    let nextLabel: String
    let nextDuration: Int?
    let foregroundColor: Color

    var body: some View {
        if !nextLabel.isEmpty {
            VStack(spacing: 4) {
                // Zone number + name on one line, like "210 W"
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    if let zone = nextZone {
                        Text("Z\(zone.rawValue)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(zone.labelColor)
                    } else {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Text(nextLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(foregroundColor)
                }

                // "UP NEXT • Zone Name  5:00"
                Group {
                    if let duration = nextDuration {
                        Text("Up Next \u{2022} \(duration.formattedDuration)")
                    } else {
                        Text("Up Next")
                    }
                }
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .monospacedDigit()
                .foregroundStyle(foregroundColor.opacity(0.6))
            }
        }
    }
}
