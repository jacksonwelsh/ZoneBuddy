import SwiftUI

struct WatchTrainerAdjustOverlay: View {
    let value: Int
    let valueSuffix: String
    let caption: String
    /// +1 most recent tick increased, -1 decreased, 0 hides the arrow.
    let direction: Int
    let zoneColor: Color

    private var arrowName: String? {
        switch direction {
        case 1: return "chevron.up"
        case -1: return "chevron.down"
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 6) {
                if let arrowName {
                    Image(systemName: arrowName)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(zoneColor)
                        .contentTransition(.symbolEffect(.replace))
                }

                Text("\(value)\(valueSuffix)")
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
        }
    }
}
