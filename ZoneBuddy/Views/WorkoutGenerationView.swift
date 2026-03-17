import SwiftUI
import SwiftData

struct WorkoutGenerationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.sortOrder) private var existingWorkouts: [Workout]

    var onWorkoutCreated: ((Workout) -> Void)?

    @State private var service = WorkoutGenerationService()
    @State private var prompt = ""
    @State private var editedName = ""

    var body: some View {
        NavigationStack {
            Group {
                switch service.state {
                case .idle:
                    promptView(error: nil)
                case .failed(let error):
                    promptView(error: error)
                case .generating:
                    generatingView
                case .completed(let workout):
                    previewView(workout)
                }
            }
            .navigationTitle("Generate Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Prompt

    private func promptView(error: Error?) -> some View {
        Form {
            Section {
                TextField("Describe your workout...", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Workout Description")
            } footer: {
                Text("e.g. \"45 minute endurance ride with tempo intervals\"")
            }

            if let error {
                Section {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Generate Workout") {
                    Task { await service.generate(from: prompt) }
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Generating

    private var generatingView: some View {
        ContentUnavailableView {
            Label("Generating Workout", systemImage: "sparkles")
        } description: {
            Text("Apple Intelligence is creating your workout...")
        } actions: {
            ProgressView()
        }
    }

    // MARK: - Preview

    private func previewView(_ generated: GeneratedWorkout) -> some View {
        let intervals = generated.intervals.enumerated().map { index, gi in
            let zone = gi.zone.flatMap { PowerZone(rawValue: $0) }
            return Interval(zone: zone, duration: gi.duration, sortOrder: index)
        }
        let totalDuration = intervals.reduce(0) { $0 + $1.duration }

        return List {
            Section {
                TextField("Workout Name", text: $editedName)
            }

            Section {
                WorkoutProgressionBar(intervals: intervals, totalDuration: totalDuration)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Intervals") {
                ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                    let isLast = index == intervals.count - 1
                    let isCooldown = isLast && interval.zone == .zone1
                    IntervalRowView(interval: interval, isCooldown: isCooldown)
                }
            }

            Section {
                Button("Save Workout") {
                    let workout = saveWorkout(name: editedName, intervals: intervals)
                    dismiss()
                    onWorkoutCreated?(workout)
                }

                Button("Regenerate") {
                    Task { await service.generate(from: prompt) }
                }

                Button("Edit Prompt") {
                    service.state = .idle
                }
            }
        }
        .onAppear { editedName = generated.name }
    }

    // MARK: - Save

    @discardableResult
    private func saveWorkout(name: String, intervals: [Interval]) -> Workout {
        for existing in existingWorkouts {
            existing.sortOrder += 1
        }
        let workout = Workout(name: name, intervals: intervals)
        workout.sortOrder = 0
        modelContext.insert(workout)
        try? modelContext.save()
        return workout
    }
}
