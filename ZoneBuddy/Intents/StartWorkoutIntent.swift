import AppIntents
import SwiftData
import Foundation

private enum StartWorkoutError: LocalizedError {
    case workoutNotFound
    var errorDescription: String? { "The workout could not be found." }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription("Starts a specific interval workout.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Workout")
    var workout: WorkoutEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let workoutModel = DataStore.shared.fetchWorkout(id: workout.id) else {
            throw StartWorkoutError.workoutNotFound
        }
        
        NavigationManager.shared.startWorkout(workoutModel)
        
        return .result(dialog: "Starting \(workout.name)")
    }
}
