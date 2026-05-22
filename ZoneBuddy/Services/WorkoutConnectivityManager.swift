import Foundation
import WatchConnectivity

@Observable
final class WorkoutConnectivityManager {
    static let shared = WorkoutConnectivityManager()

    private(set) var isWatchReachable = false
    private(set) var latestWatchHeartRate: Int?
    private(set) var watchEndedWorkout = false
    private(set) var watchPausedWorkout = false
    private(set) var watchResumedWorkout = false

    private var sessionDelegate: SessionDelegate?

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        let delegate = SessionDelegate(manager: self)
        sessionDelegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    func sendWorkoutStart(
        intervals: [Interval],
        workoutName: String,
        transitionWarningDuration: Int,
        mode: WorkoutMode = .scheduled
    ) {
        let transferIntervals = intervals.map {
            IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
        }
        let data = WorkoutTransferData(
            name: workoutName,
            transitionWarningDuration: transitionWarningDuration,
            intervals: transferIntervals,
            startedAt: Date(),
            // Route Ride has no Watch UI in v1 — bridge as a freeride
            // so the Watch shows a basic timer instead of an unknown mode.
            mode: (mode.isFreeRide || mode.isRouteRide) ? "freeride" : nil,
            goalDurationSec: mode.goalTimeSeconds,
            goalDistanceMeters: mode.goalDistanceMeters
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
        } else if message[ConnectivityMessage.pauseWorkout] != nil {
            Task { @MainActor in
                self.watchPausedWorkout = true
            }
        } else if message[ConnectivityMessage.resumeWorkout] != nil {
            Task { @MainActor in
                self.watchResumedWorkout = true
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

    func resetWatchPausedWorkout() {
        watchPausedWorkout = false
    }

    func resetWatchResumedWorkout() {
        watchResumedWorkout = false
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

#if DEBUG
extension WorkoutConnectivityManager {
    func debugSimulateInboundHR(_ bpm: Int) {
        handleReceivedMessage([ConnectivityMessage.bpmKey: bpm])
    }

    func debugSimulatePauseFromWatch() {
        handleReceivedMessage([ConnectivityMessage.pauseWorkout: true])
    }

    func debugSimulateResumeFromWatch() {
        handleReceivedMessage([ConnectivityMessage.resumeWorkout: true])
    }

    func debugSimulateEndFromWatch() {
        handleReceivedMessage([ConnectivityMessage.workoutEnded: true])
    }
}
#endif
