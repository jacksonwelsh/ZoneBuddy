import SwiftUI
import SwiftData

struct WorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let workoutData: WorkoutTransferData

    private var intervals: [Interval] {
        workoutData.intervals.enumerated().map { index, data in
            let zone = data.zone.flatMap { PowerZone(rawValue: $0) }
            return Interval(zone: zone, duration: data.duration, sortOrder: index)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkoutProgressionBar(
                        intervals: intervals,
                        totalDuration: workoutData.totalDuration
                    )
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
                    HStack {
                        Text("Transition Warning")
                        Spacer()
                        Text("\(workoutData.transitionWarningDuration)s")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(workoutData.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWorkout()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveWorkout() {
        let workout = Workout(
            name: workoutData.name,
            intervals: intervals,
            transitionWarningDuration: workoutData.transitionWarningDuration
        )
        modelContext.insert(workout)
        try? modelContext.save()
    }
}

#Preview {
    let data = WorkoutTransferData(
        name: "PZ Endurance",
        transitionWarningDuration: 10,
        intervals: [
            IntervalTransferData(zone: nil, duration: 300),
            IntervalTransferData(zone: 2, duration: 300),
            IntervalTransferData(zone: 3, duration: 180),
            IntervalTransferData(zone: 1, duration: 300),
        ]
    )
    WorkoutImportView(workoutData: data)
        .modelContainer(for: [Workout.self, Interval.self], inMemory: true)
}
