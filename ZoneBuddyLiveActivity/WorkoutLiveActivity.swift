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

        if state.isFinished {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout Complete")
                        .font(.headline)
                        .fontWeight(.bold)
                    if !context.attributes.workoutName.isEmpty {
                        Text(context.attributes.workoutName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: 1.0)
                        .tint(.green)
                }
            }
            .padding()
            .background(Color.green.opacity(0.15))
        } else {
            let currentPowerZone = state.currentZoneRawValue.flatMap(PowerZone.init(rawValue:))
            let currentColor = currentPowerZone?.color ?? .orange

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.currentLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let zoneNum = state.currentZoneRawValue {
                            Text("\(zoneNum)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                        } else {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 36))
                        }
                    }
                    Spacer()
                    timerText(state: state)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }

                if let startDate = state.intervalStartDate, let endDate = state.intervalEndDate {
                    ProgressView(timerInterval: startDate...endDate, countsDown: false)
                        .tint(currentColor)
                        .labelsHidden()
                } else {
                    ProgressView(value: state.intervalProgress)
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
            .padding()
            .background(currentColor.opacity(0.2))
        }
    }

    // MARK: - Dynamic Island Expanded

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        if state.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
        } else {
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
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        if state.isFinished {
            Text("Done!")
                .font(.system(.title2, design: .rounded).bold())
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .trailing) {
                timerText(state: state)
                    .font(.title2.weight(.semibold))
                if !state.isRunning {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        let state = context.state
        let currentPowerZone = state.currentZoneRawValue.flatMap(PowerZone.init(rawValue:))

        if state.isFinished {
            ProgressView(value: 1.0)
                .tint(.green)
        } else {
            VStack(spacing: 6) {
                if let startDate = state.intervalStartDate, let endDate = state.intervalEndDate {
                    ProgressView(timerInterval: startDate...endDate, countsDown: false)
                        .tint(currentPowerZone?.color ?? .orange)
                        .labelsHidden()
                } else {
                    ProgressView(value: state.intervalProgress)
                        .tint(currentPowerZone?.color ?? .orange)
                }

                if !state.upcomingLabel.isEmpty {
                    let nextPowerZone = state.nextZoneRawValue.flatMap(PowerZone.init(rawValue:))
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Circle()
                            .fill(nextPowerZone?.color ?? .orange)
                            .frame(width: 6, height: 6)
                        Text("Next: \(state.upcomingLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(state.currentIntervalIndex + 1)/\(context.attributes.totalIntervals)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
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
        if state.isFinished {
            Text("Done")
                .monospacedDigit()
        } else if let endDate = state.intervalEndDate {
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
            if state.isFinished {
                ZStack {
                    Circle()
                        .fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            } else if let rawValue = state.currentZoneRawValue,
               let zone = PowerZone(rawValue: rawValue) {
                ZStack {
                    Circle()
                        .fill(zone.color)
                    Text("\(rawValue)")
                        .font(.title.bold())
                        .foregroundStyle(zone.foregroundColor)
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
    currentLabel: "Tempo",
    currentIntervalIndex: 2,
    nextZoneRawValue: 5,
    upcomingLabel: "VO2 Max",
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
    upcomingLabel: "Tempo",
    intervalStartDate: .now,
    intervalEndDate: .now.addingTimeInterval(300),
    secondsRemaining: 300,
    intervalProgress: 0.0,
    isRunning: true,
    isFinished: false
)

private let finishedPreviewState = WorkoutActivityAttributes.ContentState(
    currentZoneRawValue: nil,
    currentLabel: "Done",
    currentIntervalIndex: 9,
    nextZoneRawValue: nil,
    upcomingLabel: "",
    intervalStartDate: nil,
    intervalEndDate: nil,
    secondsRemaining: 0,
    intervalProgress: 1.0,
    isRunning: false,
    isFinished: true
)

#Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
    finishedPreviewState
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
    finishedPreviewState
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
    finishedPreviewState
}

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    WorkoutLiveActivity()
} contentStates: {
    previewState
    warmupPreviewState
    finishedPreviewState
}
