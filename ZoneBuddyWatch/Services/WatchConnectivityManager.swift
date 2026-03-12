import Foundation
import WatchConnectivity

@Observable
final class WatchConnectivityManager {
    static let shared = WatchConnectivityManager()

    private var sessionDelegate: SessionDelegate?
    private var lastHRSendTime: Date = .distantPast

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        let delegate = SessionDelegate(manager: self)
        sessionDelegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
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

    fileprivate func handleReceivedMessage(_ message: [String: Any]) {
        if let data = message[ConnectivityMessage.startWorkout] as? Data,
           let workout = try? JSONDecoder().decode(WorkoutTransferData.self, from: data) {
            Task { @MainActor in
                WatchNavigationManager.shared.pendingWorkout = workout
                WatchNavigationManager.shared.shouldStartWorkout = true
            }
        } else if message[ConnectivityMessage.workoutEnded] != nil {
            Task { @MainActor in
                WatchNavigationManager.shared.shouldDismissWorkout = true
            }
        }
    }
}

private final class SessionDelegate: NSObject, WCSessionDelegate {
    private weak var manager: WatchConnectivityManager?

    init(manager: WatchConnectivityManager) {
        self.manager = manager
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.manager?.handleReceivedMessage(message)
        }
    }
}
