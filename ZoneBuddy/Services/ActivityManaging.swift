import Foundation

enum ActivityDismissalBehavior: Sendable, Equatable {
    case immediate
    case afterDelay(TimeInterval)
}

struct WorkoutActivityState: Sendable {
    let currentZoneRawValue: Int?
    let currentLabel: String
    let currentIntervalIndex: Int
    let nextZoneRawValue: Int?
    let upcomingLabel: String
    let intervalStartDate: Date?
    let intervalEndDate: Date?
    let secondsRemaining: Int
    let intervalProgress: Double
    let isRunning: Bool
    let isFinished: Bool
}

protocol ActivityManaging {
    var pushTokenHex: String? { get }
    func startActivity(workoutName: String, totalIntervals: Int, state: WorkoutActivityState)
    func updateActivity(state: WorkoutActivityState)
    func endActivity(state: WorkoutActivityState, dismissalBehavior: ActivityDismissalBehavior)
}
