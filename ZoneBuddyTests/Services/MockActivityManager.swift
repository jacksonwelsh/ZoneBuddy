import Foundation
@testable import ZoneBuddy

final class MockActivityManager: ActivityManaging {
    var pushTokenHex: String? = nil

    private(set) var startCalled = false
    private(set) var startAttributes: WorkoutActivityAttributes?
    private(set) var startState: WorkoutActivityAttributes.ContentState?

    private(set) var updateCallCount = 0
    private(set) var lastUpdateState: WorkoutActivityAttributes.ContentState?

    private(set) var endCalled = false
    private(set) var endState: WorkoutActivityAttributes.ContentState?
    private(set) var endDismissalBehavior: ActivityDismissalBehavior?

    func startActivity(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        startCalled = true
        startAttributes = attributes
        startState = state
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        updateCallCount += 1
        lastUpdateState = state
    }

    func endActivity(state: WorkoutActivityAttributes.ContentState, dismissalBehavior: ActivityDismissalBehavior) {
        endCalled = true
        endState = state
        endDismissalBehavior = dismissalBehavior
    }
}
