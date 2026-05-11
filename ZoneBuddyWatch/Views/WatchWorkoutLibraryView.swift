import SwiftUI
import SwiftData

enum WatchPlayerDestination: Hashable, Identifiable {
    case workout(Workout)
    case remote

    var id: String {
        switch self {
        case .workout(let workout): return "workout-\(workout.persistentModelID.hashValue)"
        case .remote: return "remote"
        }
    }
}

struct WatchWorkoutLibraryView: View {
    @Query(sort: \Workout.sortOrder) private var workouts: [Workout]
    // Presenting the player as a full-screen cover (rather than a nav-stack
    // push) is what lets watchOS hide the system time-of-day clock during the
    // workout: the OS only suppresses the clock in modal contexts.
    @State private var presentation: WatchPlayerDestination?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.mixed.cardio",
                        description: Text("Create workouts in the iPhone app.")
                    )
                } else {
                    List {
                        ForEach(workouts) { workout in
                            Button {
                                presentation = .workout(workout)
                            } label: {
                                WorkoutListRowView(workout: workout)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Zone Buddy")
        }
        .fullScreenCover(item: $presentation) { destination in
            switch destination {
            case .workout(let workout):
                WatchWorkoutPlayerView(workout: workout)
            case .remote:
                if let transferData = WatchNavigationManager.shared.pendingWorkout {
                    WatchWorkoutPlayerView(transferData: transferData)
                }
            }
        }
        .onChange(of: WatchNavigationManager.shared.shouldStartWorkout) { _, shouldStart in
            if shouldStart {
                presentation = .remote
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchReceivedDismiss)) { _ in
            presentation = nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !WatchNavigationManager.shared.shouldStartWorkout {
                    WatchConnectivityManager.shared.startPolling()
                }
            case .inactive, .background:
                WatchConnectivityManager.shared.stopPolling()
            @unknown default:
                break
            }
        }
        .onAppear {
            if !WatchNavigationManager.shared.shouldStartWorkout {
                WatchConnectivityManager.shared.startPolling()
            }
        }
        .onDisappear {
            WatchConnectivityManager.shared.stopPolling()
        }
    }
}

private struct WorkoutListRowView: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .font(.headline)
                .lineLimit(1)
            Text(workout.totalDuration.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
            WorkoutProgressionBar(
                intervals: workout.sortedIntervals,
                totalDuration: workout.totalDuration
            )
        }
        .padding(.vertical, 2)
    }
}
