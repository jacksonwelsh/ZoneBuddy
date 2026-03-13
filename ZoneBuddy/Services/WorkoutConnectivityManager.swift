import Foundation
import WatchConnectivity

@Observable
final class WorkoutConnectivityManager {
    static let shared = WorkoutConnectivityManager()

    private(set) var isWatchReachable = false
    private(set) var latestWatchHeartRate: Int?
    private(set) var watchEndedWorkout = false

    private var sessionDelegate: SessionDelegate?

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        let delegate = SessionDelegate(manager: self)
        sessionDelegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    func sendWorkoutStart(intervals: [Interval], workoutName: String, transitionWarningDuration: Int) {
        let transferIntervals = intervals.map {
            IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
        }
        let data = WorkoutTransferData(
            name: workoutName,
            transitionWarningDuration: transitionWarningDuration,
            intervals: transferIntervals,
            startedAt: Date()
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }

        // Persist via applicationContext so the Watch gets it even if not reachable now
        try? WCSession.default.updateApplicationContext([
            ConnectivityMessage.startWorkout: encoded
        ])

        // Also send immediately if reachable
        if WCSession.default.isReachable {
            let message: [String: Any] = [
                ConnectivityMessage.startWorkout: encoded
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
        }
    }

    func sendWorkoutEnded() {
        // Clear applicationContext so the Watch doesn't pick up a stale workout
        try? WCSession.default.updateApplicationContext([
            ConnectivityMessage.workoutEnded: true
        ])

        if WCSession.default.isReachable {
            let message: [String: Any] = [
                ConnectivityMessage.workoutEnded: true
            ]
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
        }
    }

    fileprivate func handleReceivedMessage(_ message: [String: Any]) {
        if let bpm = message[ConnectivityMessage.bpmKey] as? Int {
            Task { @MainActor in
                self.latestWatchHeartRate = bpm
            }
        } else if message[ConnectivityMessage.workoutEnded] != nil {
            Task { @MainActor in
                self.watchEndedWorkout = true
            }
        }
    }

    fileprivate func handleReceivedMessage(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message[ConnectivityMessage.requestActiveWorkout] != nil {
            Task { @MainActor in
                guard let vm = WorkoutSessionManager.shared.activeViewModel, vm.isRunning else {
                    replyHandler([:])
                    return
                }
                // Build transfer data from the active ViewModel
                let transferIntervals = vm.intervals.map {
                    IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
                }
                let data = WorkoutTransferData(
                    name: vm.workoutName,
                    transitionWarningDuration: vm.transitionWarningDuration,
                    intervals: transferIntervals,
                    startedAt: Date().addingTimeInterval(TimeInterval(-vm.totalElapsedSeconds))
                )
                if let encoded = try? JSONEncoder().encode(data) {
                    replyHandler([ConnectivityMessage.activeWorkoutResponse: encoded])
                } else {
                    replyHandler([:])
                }
            }
        } else {
            handleReceivedMessage(message)
            replyHandler([:])
        }
    }

    func clearHeartRate() {
        latestWatchHeartRate = nil
    }

    func resetWatchEndedWorkout() {
        watchEndedWorkout = false
    }

    fileprivate func updateReachability(_ reachable: Bool) {
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
    }
}

private final class SessionDelegate: NSObject, WCSessionDelegate {
    private weak var manager: WorkoutConnectivityManager?

    init(manager: WorkoutConnectivityManager) {
        self.manager = manager
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.manager?.updateReachability(session.isReachable)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.manager?.updateReachability(session.isReachable)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.manager?.handleReceivedMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.manager?.handleReceivedMessage(message, replyHandler: replyHandler)
        }
    }
}
