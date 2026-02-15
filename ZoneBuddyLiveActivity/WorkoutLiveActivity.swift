import ActivityKit
import SwiftUI
import WidgetKit
import ZoneBuddy // Added import for PowerZone and formattedDuration

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
                    zoneColorDot(for: PowerZone(rawValue: context.state.currentZoneRawValue ?? 1))
                    zoneName(for: PowerZone(rawValue: context.state.currentZoneRawValue ?? 1))
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
        let currentPowerZone = PowerZone(rawValue: state.currentZoneRawValue ?? 1)
        let currentColor = currentPowerZone?.color ?? .gray

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
                    let nextPowerZone = PowerZone(rawValue: state.nextZoneRawValue ?? 1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(nextPowerZone?.color ?? .gray)
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
        let currentPowerZone = PowerZone(rawValue: state.currentZoneRawValue ?? 1)
        
        VStack(spacing: 8) {
            ProgressView(value: state.intervalProgress)
                .tint(currentPowerZone?.color ?? .gray)

            if !state.upcomingLabel.isEmpty {
                let nextPowerZone = PowerZone(rawValue: state.nextZoneRawValue ?? 1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(nextPowerZone?.color ?? .gray)
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
            .frame(width: 12, height: 12)
    }
    
    @ViewBuilder
    private func zoneName(for zone: PowerZone?) -> some View {
        if let zone = zone {
            Text(zone.displayName)
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
            Text(state.secondsRemaining.formattedDuration) // Assuming formattedDuration is now shared via extension
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func minimalView(state: WorkoutActivityAttributes.ContentState) -> some View {
        let currentPowerZone = PowerZone(rawValue: state.currentZoneRawValue ?? 1)
        let color = currentPowerZone?.color ?? .gray

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
}