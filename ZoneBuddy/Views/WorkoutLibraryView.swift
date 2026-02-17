import SwiftUI
import SwiftData

struct WorkoutLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.createdAt, order: .reverse) private var workouts: [Workout]
    @State private var navigateToNewWorkout: Workout?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
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
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(workouts[index])
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
                        let workout = Workout(name: "New Workout")
                        modelContext.insert(workout)
                        try? modelContext.save()
                        navigateToNewWorkout = workout
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

#Preview("Empty Library") {
    WorkoutLibraryView()
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
    return WorkoutLibraryView()
        .modelContainer(container)
}
