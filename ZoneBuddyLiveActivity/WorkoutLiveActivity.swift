import ActivityKit
import SwiftUI
import WidgetKit

private extension Int {
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    zoneColorDot(zoneRawValue: context.state.currentZoneRawValue)
                    zoneName(zoneRawValue: context.state.currentZoneRawValue)
                }
            } compactTrailing: {
                timerText(state: context.state)
            } minimal: {
                minimalView(state: context.state)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        let currentColor = zoneColor(for: state.currentZoneRawValue)

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.currentLabel)
                    .font(.headline)

                if let zoneNum = state.currentZoneRawValue {
                    Text("\(zoneNum)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 36))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                timerText(state: state)
                    .font(.system(.title, design: .monospaced))

                ProgressView(value: state.intervalProgress)
                    .tint(currentColor)

                if !state.upcomingLabel.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(zoneColor(for: state.nextZoneRawValue))
                            .frame(width: 8, height: 8)
                        Text("Next: \(state.upcomingLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(currentColor.opacity(0.2))
    }

    // MARK: - Dynamic Island Expanded

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        VStack(alignment: .leading) {
            if let zoneNum = state.currentZoneRawValue {
                Text("\(zoneNum)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            } else {
                Image(systemName: "flame.fill")
                    .font(.title)
            }
            Text(state.currentLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        VStack(alignment: .trailing) {
            timerText(state: state)
                .font(.system(.title2, design: .monospaced))
            if !state.isRunning && !state.isFinished {
                Text("Paused")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        let color = zoneColor(for: state.currentZoneRawValue)

        VStack(spacing: 8) {
            ProgressView(value: state.intervalProgress)
                .tint(color)

            if !state.upcomingLabel.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(zoneColor(for: state.nextZoneRawValue))
                        .frame(width: 8, height: 8)
                        .offset(x: 4)
                    Text("Next: \(state.upcomingLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.currentIntervalIndex + 1)/\(context.attributes.totalIntervals)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(x: -4)
                }
            }
        }
    }

    // MARK: - Compact & Minimal

    @ViewBuilder
    private func zoneColorDot(zoneRawValue: Int?) -> some View {
        Circle()
            .fill(zoneColor(for: zoneRawValue))
            .frame(width: 12, height: 12)
    }
    
    @ViewBuilder
    private func zoneName(zoneRawValue: Int?) -> some View {
        if let zoneNum = zoneRawValue {
            Text("Zone \(zoneNum)")
                .font(.caption.bold())
        } else {
            Text("Unknown")
                .font(.caption.bold())
        }
    }

    @ViewBuilder
    private func timerText(state: WorkoutActivityAttributes.ContentState) -> some View {
        if let endDate = state.intervalEndDate {
            Text(timerInterval: Date()...endDate, countsDown: true)
                .monospacedDigit()
        } else {
            Text(state.secondsRemaining.formattedDuration)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func minimalView(state: WorkoutActivityAttributes.ContentState) -> some View {
        let color = zoneColor(for: state.currentZoneRawValue)

        ZStack {
            Circle()
                .fill(color)
            if let zoneNum = state.currentZoneRawValue {
                Text("\(zoneNum)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Helpers

    private static let zoneColors: [Int: Color] = [
        1: Color(red: 0.63, green: 0.63, blue: 0.63),
        2: Color(red: 0.00, green: 0.47, blue: 1.00),
        3: Color(red: 0.00, green: 0.80, blue: 0.00),
        4: Color(red: 1.00, green: 0.84, blue: 0.00),
        5: Color(red: 1.00, green: 0.55, blue: 0.00),
        6: Color(red: 1.00, green: 0.13, blue: 0.00),
        7: Color(red: 0.55, green: 0.00, blue: 1.00),
    ]

    private func zoneColor(for rawValue: Int?) -> Color {
        guard let rawValue else { return .gray }
        return Self.zoneColors[rawValue] ?? .gray
    }
}
