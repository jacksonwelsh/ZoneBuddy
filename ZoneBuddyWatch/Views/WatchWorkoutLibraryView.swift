import SwiftUI
import SwiftData

enum WatchPlayerDestination: Hashable {
    case workout(Workout)
    case remote
}

struct WatchWorkoutLibraryView: View {
    @Query(sort: \Workout.sortOrder) private var workouts: [Workout]
    @State private var navigationPath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                            NavigationLink(value: WatchPlayerDestination.workout(workout)) {
                                WorkoutListRowView(workout: workout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Zone Buddy")
            .navigationDestination(for: WatchPlayerDestination.self) { destination in
                switch destination {
                case .workout(let workout):
                    WatchWorkoutPlayerView(workout: workout)
                case .remote:
                    if let transferData = WatchNavigationManager.shared.pendingWorkout {
                        WatchWorkoutPlayerView(transferData: transferData)
                    }
                }
            }
        }
        .onChange(of: WatchNavigationManager.shared.shouldStartWorkout) { _, shouldStart in
            if shouldStart {
                navigationPath.append(WatchPlayerDestination.remote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchReceivedDismiss)) { _ in
            if !navigationPath.isEmpty {
                navigationPath = NavigationPath()
            }
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
            // If a remote-start signal landed before the view was wired up to observe it
            // (e.g. during a fresh launch into an in-progress iPad workout), `.onChange`
            // will never fire — pick it up here instead.
            if WatchNavigationManager.shared.shouldStartWorkout && navigationPath.isEmpty {
                navigationPath.append(WatchPlayerDestination.remote)
            } else {
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
