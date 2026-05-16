import SwiftUI

private enum GoalType: String, CaseIterable, Identifiable {
    case none = "None"
    case time = "Time"
    case distance = "Distance"

    var id: String { rawValue }
}

struct FreeRideSetupView: View {
    @State private var goalType: GoalType = .none
    @State private var goalMinutes: Int = 30
    @State private var goalDistanceWhole: Int = 20
    @State private var navigateToPlayer = false
    @State private var showingBikePrompt = false

    private var goal: FreeRideGoal? {
        switch goalType {
        case .none:
            return nil
        case .time:
            return .time(seconds: goalMinutes * 60)
        case .distance:
            let meters = UnitFormatting.usesMetric
                ? Double(goalDistanceWhole) * 1000.0
                : Double(goalDistanceWhole) * 1609.344
            return .distance(meters: meters)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Goal", selection: $goalType) {
                    ForEach(GoalType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Goal")
            } footer: {
                Text(footerText)
            }

            if goalType == .time {
                Section("Duration") {
                    Picker("Minutes", selection: $goalMinutes) {
                        ForEach(stride(from: 5, through: 180, by: 5).map { $0 }, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                }
            }

            if goalType == .distance {
                Section("Distance") {
                    Picker("Distance", selection: $goalDistanceWhole) {
                        ForEach(stride(from: 5, through: 100, by: 1).map { $0 }, id: \.self) { d in
                            Text("\(d) \(UnitFormatting.distanceUnit)").tag(d)
                        }
                    }
                }
            }
        }
        .navigationTitle("Free Ride")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let bikeManager = BikeManagerProvider.current
                    let promptEnabled = SettingsManager.shared.promptForBikeBeforeWorkout
                    let bikeReady = bikeManager.isConnected && bikeManager.hasReceivedNonZeroMetric
                    if promptEnabled && !bikeReady {
                        showingBikePrompt = true
                    } else {
                        navigateToPlayer = true
                    }
                } label: {
                    Label("Start Ride", systemImage: "play.fill")
                }
            }
        }
        .navigationDestination(isPresented: $navigateToPlayer) {
            WorkoutPlayerView(
                intervals: [],
                workoutName: "Free Ride",
                transitionWarningDuration: 0,
                mode: .freeRide(goal: goal)
            )
        }
        .sheet(isPresented: $showingBikePrompt) {
            BikePromptSheet(onStart: {
                showingBikePrompt = false
                navigateToPlayer = true
            })
        }
    }

    private var footerText: String {
        switch goalType {
        case .none:
            return "The ride continues until you tap Exit."
        case .time:
            return "The ride ends automatically when the duration is reached."
        case .distance:
            return "The ride ends automatically when the distance is reached."
        }
    }
}

#Preview {
    NavigationStack {
        FreeRideSetupView()
    }
}
