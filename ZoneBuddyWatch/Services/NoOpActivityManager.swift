import Foundation

final class NoOpActivityManager: ActivityManaging {
    var pushTokenHex: String? { nil }
    func startActivity(workoutName: String, totalIntervals: Int, state: WorkoutActivityState) {}
    func updateActivity(state: WorkoutActivityState) {}
    func endActivity(state: WorkoutActivityState, dismissalBehavior: ActivityDismissalBehavior) {}
}
