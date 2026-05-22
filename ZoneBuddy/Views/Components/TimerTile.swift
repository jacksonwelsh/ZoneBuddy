import SwiftUI

struct TimerTile: View {
    let secondsRemaining: Int
    let intervalDuration: Int
    let foregroundColor: Color

    private var elapsed: Int {
        max(intervalDuration - secondsRemaining, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(secondsRemaining.formattedDuration)
                .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(foregroundColor)
                .contentTransition(.numericText())

            // No interval (Route Ride, unstructured Free Ride) → the big
            // number is already the elapsed time; the stopwatch row would
            // just duplicate it / show 00:00. Suppress it in that case.
            if intervalDuration > 0 {
                HStack(spacing: 16) {
                    Label(elapsed.formattedDuration, systemImage: "stopwatch")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor.opacity(0.6))
                }
            }
        }
    }
}
