import ActivityKit
import SwiftUI
import WidgetKit


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
                minimalView(state: context.state)
            } compactTrailing: {
                timerText(state: context.state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentMargins(-5)
            } minimal: {
                minimalView(state: context.state)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        let currentPowerZone = state.currentZoneRawValue.flatMap(PowerZone.init(rawValue:))
        let currentColor = currentPowerZone?.color ?? .orange

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

                if let startDate = state.intervalStartDate, let endDate = state.intervalEndDate, !state.isFinished {
                    ProgressView(
                        timerInterval: startDate...endDate,
                        countsDown: false
                    )
                    .tint(currentColor)
                } else {
                    ProgressView(value: state.isFinished ? 1.0 : 0.0)
                        .tint(currentColor)
                }

                if !state.upcomingLabel.isEmpty {
                    let nextPowerZone = state.nextZoneRawValue.flatMap(PowerZone.init(rawValue:))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(nextPowerZone?.color ?? .orange)
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
        let currentPowerZone = state.currentZoneRawValue.flatMap(PowerZone.init(rawValue:))

        VStack(spacing: 8) {
            if let startDate = state.intervalStartDate, let endDate = state.intervalEndDate, !state.isFinished {
                ProgressView(
                    timerInterval: startDate...endDate,
                    countsDown: false
                )
                .tint(currentPowerZone?.color ?? .orange)
            } else {
                ProgressView(value: state.isFinished ? 1.0 : 0.0)
                    .tint(currentPowerZone?.color ?? .orange)
            }

            if !state.upcomingLabel.isEmpty {
                let nextPowerZone = state.nextZoneRawValue.flatMap(PowerZone.init(rawValue:))
                HStack(spacing: 4) {
                    Circle()
                        .fill(nextPowerZone?.color ?? .orange)
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
    private func zoneColorDot(for zone: PowerZone?) -> some View {
        Circle()
            .fill(zone?.color ?? Color.gray)
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private func timerText(state: WorkoutActivityAttributes.ContentState) -> some View {
        if let endDate = state.intervalEndDate {
            // Sneaky little trick to force the container to use only the space necessary
            Text("88:88")
                .monospacedDigit()
                .hidden()
                .overlay {
                    Text(timerInterval: Date()...endDate, countsDown: true, showsHours: false)
                        .monospacedDigit()
                        .frame(alignment: .trailing)
                }
        } else {
            Text(state.secondsRemaining.formattedDuration)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func minimalView(state: WorkoutActivityAttributes.ContentState) -> some View {
        Group {
            if let rawValue = state.currentZoneRawValue,
               let zone = PowerZone(rawValue: rawValue) {
                ZStack {
                    Circle()
                        .fill(zone.color)
                    Text("\(rawValue)")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.8))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Previews

private let previewAttributes = WorkoutActivityAttributes(
    workoutName: "Power Zone Endurance",
    totalIntervals: 10
)

private let previewState = WorkoutActivityAttributes.ContentState(
    currentZoneRawValue: 3,
    currentLabel: "Zone 3",
    currentIntervalIndex: 2,
    nextZoneRawValue: 5,
    upcomingLabel: "Zone 5",
    intervalStartDate: .now,
    intervalEndDate: .now.addingTimeInterval(180),
    secondsRemaining: 180,
    intervalProgress: 0.4,
    isRunning: true,
    isFinished: false
)

private let warmupPreviewState = WorkoutActivityAttributes.ContentState(
    currentZoneRawValue: nil,
    currentLabel: "Warmup",
    currentIntervalIndex: 0,
    nextZoneRawValue: 3,
    upcomingLabel: "Zone 3",
    intervalStartDate: .now,
    intervalEndDate: .now.addingTimeInterval(300),
    secondsRemaining: 300,
    intervalProgress: 0.0,
    isRunning: true,
    isFinished: false
)

#Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
}

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
}
