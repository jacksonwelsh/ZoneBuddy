import Foundation
import WatchConnectivity

@Observable
final class WatchConnectivityManager {
    static let shared = WatchConnectivityManager()

    private var sessionDelegate: SessionDelegate?
    private var lastHRSendTime: Date = .distantPast
    private var pollTask: Task<Void, Never>?
    private(set) var isPolling = false

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        let delegate = SessionDelegate(manager: self)
        sessionDelegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    func sendWorkoutPaused() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [ConnectivityMessage.pauseWorkout: true],
            replyHandler: nil
        ) { _ in }
    }

    func sendWorkoutResumed() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [ConnectivityMessage.resumeWorkout: true],
            replyHandler: nil
        ) { _ in }
    }

    func sendWorkoutEnded() {
        guard WCSession.default.isReachable else { return }
        let message: [String: Any] = [
            ConnectivityMessage.workoutEnded: true
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
    }

    func sendHeartRate(_ bpm: Int) {
        guard WCSession.default.isReachable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHRSendTime) >= 1.0 else { return }
        lastHRSendTime = now

        let message: [String: Any] = [
            ConnectivityMessage.bpmKey: bpm,
            ConnectivityMessage.timestampKey: now.timeIntervalSince1970
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
    }

    // MARK: - Polling for active workout

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                // Don't poll if we already have a workout active
                if WatchNavigationManager.shared.shouldStartWorkout {
                    break
                }
                pollForActiveWorkout()
                try? await Task.sleep(for: .seconds(5))
            }
            isPolling = false
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func pollForActiveWorkout() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [ConnectivityMessage.requestActiveWorkout: true],
            replyHandler: { reply in
                Task { @MainActor in
                    self.handleActiveWorkoutResponse(reply)
                }
            },
            errorHandler: { _ in }
        )
    }

    private func handleActiveWorkoutResponse(_ reply: [String: Any]) {
        guard let data = reply[ConnectivityMessage.activeWorkoutResponse] as? Data,
              let workout = try? JSONDecoder().decode(WorkoutTransferData.self, from: data) else {
            return
        }
        // Only navigate if we're not already showing a workout
        guard !WatchNavigationManager.shared.shouldStartWorkout else { return }
        WatchNavigationManager.shared.pendingWorkout = workout
        WatchNavigationManager.shared.shouldStartWorkout = true
        stopPolling()
    }

    // MARK: - Message handling

    fileprivate func handleReceivedMessage(_ message: [String: Any]) {
        if let data = message[ConnectivityMessage.startWorkout] as? Data,
           let workout = try? JSONDecoder().decode(WorkoutTransferData.self, from: data) {
            Task { @MainActor in
                WatchNavigationManager.shared.pendingWorkout = workout
                WatchNavigationManager.shared.shouldStartWorkout = true
                self.stopPolling()
            }
        } else if message[ConnectivityMessage.workoutEnded] != nil {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchReceivedDismiss, object: nil)
            }
        } else if message[ConnectivityMessage.pauseWorkout] != nil {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchReceivedPause, object: nil)
            }
        } else if message[ConnectivityMessage.resumeWorkout] != nil {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchReceivedResume, object: nil)
            }
        }
    }

    fileprivate func handleApplicationContext(_ context: [String: Any]) {
        if let data = context[ConnectivityMessage.startWorkout] as? Data,
           let workout = try? JSONDecoder().decode(WorkoutTransferData.self, from: data) {
            // Only navigate if we're not already in a workout
            guard !WatchNavigationManager.shared.shouldStartWorkout else { return }
            WatchNavigationManager.shared.pendingWorkout = workout
            WatchNavigationManager.shared.shouldStartWorkout = true
            stopPolling()
        } else if context[ConnectivityMessage.workoutEnded] != nil {
            NotificationCenter.default.post(name: .watchReceivedDismiss, object: nil)
        }
    }

    fileprivate func handleActivationComplete() {
        // Check for pending workout data in receivedApplicationContext
        let context = WCSession.default.receivedApplicationContext
        guard !context.isEmpty else { return }
        Task { @MainActor in
            self.handleApplicationContext(context)
        }
    }
}

private final class SessionDelegate: NSObject, WCSessionDelegate {
    private weak var manager: WatchConnectivityManager?

    init(manager: WatchConnectivityManager) {
        self.manager = manager
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.manager?.handleActivationComplete()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.manager?.handleReceivedMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.manager?.handleApplicationContext(applicationContext)
        }
    }
}
