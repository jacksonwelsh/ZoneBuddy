import ActivityKit
import Foundation

final class LiveActivityManager: ActivityManaging {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var pendingUpdate: Task<Void, Never>?
    private var pushTokenTask: Task<Void, Never>?
    private(set) var pushTokenHex: String?

    func startActivity(workoutName: String, totalIntervals: Int, state: WorkoutActivityState) {
        let attributes = WorkoutActivityAttributes(workoutName: workoutName, totalIntervals: totalIntervals)
        let contentState = contentState(from: state)
        Task.detached {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: contentState, staleDate: nil),
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

    func updateActivity(state: WorkoutActivityState) {
        guard let activity else { return }
        // Cancel any in-flight update so they don't pile up and queue behind each other.
        // This ensures we always push the latest state without blocking the caller.
        pendingUpdate?.cancel()
        let content = ActivityContent(state: contentState(from: state), staleDate: nil)
        pendingUpdate = Task.detached(priority: .high) {
            guard !Task.isCancelled else { return }
            await activity.update(content)
        }
    }

    func endActivity(state: WorkoutActivityState, dismissalBehavior: ActivityDismissalBehavior) {
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
        let content = ActivityContent(state: contentState(from: state), staleDate: nil)
        self.activity = nil
        Task.detached(priority: .high) {
            await activity.end(content, dismissalPolicy: policy)
        }
    }

    private func contentState(from state: WorkoutActivityState) -> WorkoutActivityAttributes.ContentState {
        .init(
            currentZoneRawValue: state.currentZoneRawValue,
            currentLabel: state.currentLabel,
            currentIntervalIndex: state.currentIntervalIndex,
            nextZoneRawValue: state.nextZoneRawValue,
            upcomingLabel: state.upcomingLabel,
            intervalStartDate: state.intervalStartDate,
            intervalEndDate: state.intervalEndDate,
            secondsRemaining: state.secondsRemaining,
            intervalProgress: state.intervalProgress,
            isRunning: state.isRunning,
            isFinished: state.isFinished
        )
    }
}
