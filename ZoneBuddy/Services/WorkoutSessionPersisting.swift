import Foundation
import SwiftData
import os

/// Persists a completed `WorkoutSession` (with its interval snapshots) to durable storage.
/// Injected into `WorkoutPlayerViewModel` so the player can be exercised in tests without
/// touching the global `DataStore.shared`.
protocol WorkoutSessionPersisting {
    /// Inserts the session and its interval snapshots, then returns the persisted session
    /// on success or nil if the save failed.
    @discardableResult
    func save(_ session: WorkoutSession, intervals: [SessionInterval]) -> WorkoutSession?
}

/// Default persister: writes through the app's main SwiftData context.
struct LiveWorkoutSessionPersister: WorkoutSessionPersisting {
    private static let logger = Logger(subsystem: "dev.jacksn.ZoneBuddy", category: "WorkoutSessionPersister")

    let context: ModelContext

    @discardableResult
    func save(_ session: WorkoutSession, intervals: [SessionInterval]) -> WorkoutSession? {
        context.insert(session)
        for interval in intervals {
            context.insert(interval)
        }
        do {
            try context.save()
            return session
        } catch {
            Self.logger.error("Failed to save WorkoutSession: \(error, privacy: .public)")
            return nil
        }
    }
}
