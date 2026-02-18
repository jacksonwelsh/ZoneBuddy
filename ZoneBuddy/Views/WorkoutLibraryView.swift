import SwiftUI
import SwiftData

private enum PlayerDestination: Hashable { case player }

struct WorkoutLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.sortOrder) private var workouts: [Workout]
    @State private var navigateToNewWorkout: Workout?
    @State private var showSettings = false
    @State private var navigationPath = NavigationPath()
    @Binding var pendingImport: WorkoutTransferData?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading) {
                                Text(workout.name)
                                    .font(.headline)
                                Text("\((workout.intervals ?? []).count) intervals \u{2022} \(workout.totalDuration.formattedDuration)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            WorkoutProgressionBar(
                                intervals: workout.sortedIntervals,
                                totalDuration: workout.totalDuration
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .leading) {
                        ShareWorkoutButton(workout: workout)
                            .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(workouts[index])
                    }
                    reindex()
                    try? modelContext.save()
                }
                .onMove { source, destination in
                    var reordered = workouts
                    reordered.move(fromOffsets: source, toOffset: destination)
                    for (index, workout) in reordered.enumerated() {
                        workout.sortOrder = index
                    }
                    try? modelContext.save()
                }
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts",
                        systemImage: "figure.indoor.cycle",
                        description: Text("Tap + to create your first workout.")
                    )
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: Workout.self) { workout in
                WorkoutEditorView(workout: workout)
            }
            .navigationDestination(item: $navigateToNewWorkout) { workout in
                WorkoutEditorView(workout: workout, isNew: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addWorkoutToTop(Workout(name: "New Workout"), navigate: true)
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: PlayerDestination.self) { _ in
                playerDestination()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $pendingImport) { data in
                WorkoutImportView(workoutData: data)
            }
            .onAppear {
                // Handle cold-launch: intent may fire before onChange attaches
                if NavigationManager.shared.shouldStartWorkout,
                   NavigationManager.shared.selectedWorkout != nil {
                    navigationPath.append(PlayerDestination.player)
                    NavigationManager.shared.shouldStartWorkout = false
                }
            }
            .onChange(of: NavigationManager.shared.shouldStartWorkout) { _, shouldStart in
                if shouldStart, NavigationManager.shared.selectedWorkout != nil {
                    navigationPath.append(PlayerDestination.player)
                    NavigationManager.shared.shouldStartWorkout = false
                }
            }
        }
    }

    @ViewBuilder
    private func playerDestination() -> some View {
        if let workout = NavigationManager.shared.selectedWorkout {
            WorkoutPlayerView(
                intervals: workout.sortedIntervals,
                workoutName: workout.name,
                transitionWarningDuration: workout.transitionWarningDuration
            )
        } else {
            ContentUnavailableView("Workout Unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private func addWorkoutToTop(_ workout: Workout, navigate: Bool = false) {
        for existing in workouts {
            existing.sortOrder += 1
        }
        workout.sortOrder = 0
        modelContext.insert(workout)
        try? modelContext.save()
        if navigate {
            navigateToNewWorkout = workout
        }
    }

    private func reindex() {
        for (index, workout) in workouts.enumerated() {
            workout.sortOrder = index
        }
    }
}

#Preview("Empty Library") {
    WorkoutLibraryView(pendingImport: .constant(nil))
        .modelContainer(for: [Workout.self, Interval.self], inMemory: true)
}

#Preview("With Workouts") {
    let container = try! ModelContainer(for: Workout.self, Interval.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let w1 = Workout(name: "PZ Endurance", intervals: [
        Interval(zone: .zone2, duration: 300, sortOrder: 0),
        Interval(zone: .zone3, duration: 300, sortOrder: 1),
        Interval(zone: .zone2, duration: 300, sortOrder: 2),
        Interval(zone: .zone1, duration: 300, sortOrder: 3),
    ])
    let w2 = Workout(name: "PZ Max", intervals: [
        Interval(zone: .zone3, duration: 120, sortOrder: 0),
        Interval(zone: .zone6, duration: 60, sortOrder: 1),
        Interval(zone: .zone3, duration: 120, sortOrder: 2),
    ])
    context.insert(w1)
    context.insert(w2)
    return WorkoutLibraryView(pendingImport: .constant(nil))
        .modelContainer(container)
}
