import Foundation
@testable import ZoneBuddy

final class CountingSessionPersister: WorkoutSessionPersisting {
    private(set) var saveCount = 0
    private(set) var lastSession: WorkoutSession?

    func save(_ session: WorkoutSession, intervals: [SessionInterval]) -> WorkoutSession? {
        saveCount += 1
        lastSession = session
        return session
    }
}
