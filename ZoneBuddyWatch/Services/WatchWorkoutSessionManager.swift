import WatchKit

final class WatchWorkoutSessionManager: NSObject {
    static let shared = WatchWorkoutSessionManager()
    private var session: WKExtendedRuntimeSession?
    private var sessionDelegate: SessionDelegate?

    private override init() {
        super.init()
    }

    func startSession() {
        guard session == nil else { return }
        let d = SessionDelegate(manager: self)
        sessionDelegate = d
        let s = WKExtendedRuntimeSession()
        s.delegate = d
        s.start()
        session = s
    }

    func endSession() {
        session?.invalidate()
        session = nil
        sessionDelegate = nil
    }

    fileprivate func sessionExpired() {
        session = nil
        sessionDelegate = nil
        startSession()
    }

    fileprivate func sessionInvalidated() {
        session = nil
        sessionDelegate = nil
    }
}

private final class SessionDelegate: NSObject, WKExtendedRuntimeSessionDelegate {
    private weak var manager: WatchWorkoutSessionManager?

    init(manager: WatchWorkoutSessionManager) {
        self.manager = manager
    }

    func extendedRuntimeSessionDidExpire(_ session: WKExtendedRuntimeSession) {
        manager?.sessionExpired()
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        manager?.sessionInvalidated()
    }
}
