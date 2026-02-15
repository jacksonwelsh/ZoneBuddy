import ActivityKit
import Foundation

enum ActivityDismissalBehavior: Sendable, Equatable {
    case immediate
    case afterDelay(TimeInterval)
}

protocol ActivityManaging {
    func startActivity(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState)
    func updateActivity(state: WorkoutActivityAttributes.ContentState)
    func endActivity(state: WorkoutActivityAttributes.ContentState, dismissalBehavior: ActivityDismissalBehavior)
}

final class LiveActivityManager: ActivityManaging {
    private var activity: Activity<WorkoutActivityAttributes>?

    func startActivity(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity(state: WorkoutActivityAttributes.ContentState, dismissalBehavior: ActivityDismissalBehavior) {
        guard let activity else { return }
        let policy: ActivityUIDismissalPolicy
        switch dismissalBehavior {
        case .immediate:
            policy = .immediate
        case .afterDelay(let interval):
            policy = .after(Date().addingTimeInterval(interval))
        }
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: policy)
        }
        self.activity = nil
    }
}
