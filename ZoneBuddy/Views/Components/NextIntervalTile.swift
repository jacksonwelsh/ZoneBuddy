import SwiftUI

struct NextIntervalTile: View {
    let nextZone: PowerZone?
    let nextLabel: String
    let nextDuration: Int?
    let foregroundColor: Color

    var body: some View {
        if !nextLabel.isEmpty {
            HStack(spacing: 12) {
                Text("UP NEXT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .tracking(1)
                    .foregroundStyle(foregroundColor.opacity(0.5))

                if let zone = nextZone {
                    Circle()
                        .fill(zone.color)
                        .frame(width: 10, height: 10)
                }

                Text(nextLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(foregroundColor)

                if let duration = nextDuration {
                    Text(duration.formattedDuration)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor.opacity(0.7))
                }

                Spacer()
            }
        }
    }
}
