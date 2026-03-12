import Foundation
@testable import ZoneBuddy

final class MockActivityManager: ActivityManaging {
    var pushTokenHex: String? = nil

    private(set) var startCalled = false
    private(set) var startWorkoutName: String?
    private(set) var startTotalIntervals: Int?
    private(set) var startState: WorkoutActivityState?

    private(set) var updateCallCount = 0
    private(set) var lastUpdateState: WorkoutActivityState?

    private(set) var endCalled = false
    private(set) var endState: WorkoutActivityState?
    private(set) var endDismissalBehavior: ActivityDismissalBehavior?

    func startActivity(workoutName: String, totalIntervals: Int, state: WorkoutActivityState) {
        startCalled = true
        startWorkoutName = workoutName
        startTotalIntervals = totalIntervals
        startState = state
    }

    func updateActivity(state: WorkoutActivityState) {
        updateCallCount += 1
        lastUpdateState = state
    }

    func endActivity(state: WorkoutActivityState, dismissalBehavior: ActivityDismissalBehavior) {
        endCalled = true
        endState = state
        endDismissalBehavior = dismissalBehavior
    }
}
