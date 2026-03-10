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
    var pushTokenHex: String? { get }
}

final class LiveActivityManager: ActivityManaging {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var pendingUpdate: Task<Void, Never>?
    private var pushTokenTask: Task<Void, Never>?
    private(set) var pushTokenHex: String?

    func startActivity(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        Task.detached {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: .token
                )
                await MainActor.run {
                    self.activity = activity
                    self.observePushToken(activity)
                }
            } catch {
                print("Failed to start Live Activity: \(error)")
            }
        }
    }

    private func observePushToken(_ activity: Activity<WorkoutActivityAttributes>) {
        pushTokenTask?.cancel()
        pushTokenTask = Task.detached {
            for await tokenData in activity.pushTokenUpdates {
                let hex = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run { self.pushTokenHex = hex }
            }
        }
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        // Cancel any in-flight update so they don't pile up and queue behind each other.
        // This ensures we always push the latest state without blocking the caller.
        pendingUpdate?.cancel()
        let content = ActivityContent(state: state, staleDate: nil)
        pendingUpdate = Task.detached(priority: .high) {
            guard !Task.isCancelled else { return }
            await activity.update(content)
        }
    }

    func endActivity(state: WorkoutActivityAttributes.ContentState, dismissalBehavior: ActivityDismissalBehavior) {
        guard let activity else { return }
        pendingUpdate?.cancel()
        pendingUpdate = nil
        pushTokenTask?.cancel()
        pushTokenTask = nil
        pushTokenHex = nil
        let policy: ActivityUIDismissalPolicy
        switch dismissalBehavior {
        case .immediate:
            policy = .immediate
        case .afterDelay(let interval):
            policy = .after(Date().addingTimeInterval(interval))
        }
        let content = ActivityContent(state: state, staleDate: nil)
        self.activity = nil
        Task.detached(priority: .high) {
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}
