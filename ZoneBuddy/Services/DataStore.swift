import Foundation
import SwiftData
import os

@MainActor
final class DataStore {
    static let shared = DataStore()

    static let logger = Logger(subsystem: "dev.jacksn.ZoneBuddy", category: "DataStore")

    let container: ModelContainer
    let context: ModelContext

    /// True when the CloudKit-backed configuration failed and we fell back to local-only storage.
    /// Surfaceable by the UI so users know iCloud sync is off for this session.
    let isCloudKitDisabled: Bool

    private init() {
        let schema = Schema([
            Workout.self,
            Interval.self,
            WorkoutSession.self,
            SessionInterval.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            isCloudKitDisabled = false
        } catch {
            // CloudKit-backed container failed. Log the cause and fall back to local-only
            // storage; the user keeps a working app but loses iCloud sync until next launch.
            Self.logger.error("CloudKit-backed ModelContainer failed, falling back to local-only: \(error, privacy: .public)")
            let fallback = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                container = try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                Self.logger.fault("Local-only ModelContainer also failed: \(error, privacy: .public)")
                fatalError("Unable to initialize ModelContainer: \(error)")
            }
            isCloudKitDisabled = true
        }
        context = container.mainContext
    }
    
    func fetchWorkouts() -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func fetchWorkout(id: UUID) -> Workout? {
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    func fetchSessions() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

#if DEBUG
    /// Stable UUID so re-launches reuse (and re-seed updated values into) the same row.
    private static let rainbowWorkoutID = UUID(uuidString: "DEBA6601-0000-0000-0000-7A1B0C0E0F0F")!

    /// Inserts (or refreshes) a "Rainbow" workout that ramps Zone 1 → Zone 7 for 10s
    /// each and ends with a 10s Zone 1 cooldown — useful for eyeballing the edge-glow
    /// color transitions across every zone in ~80 seconds.
    func seedRainbowWorkoutIfNeeded() {
        let id = Self.rainbowWorkoutID
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }

        let zones = PowerZone.allCases.sorted { $0.rawValue < $1.rawValue }
        var intervals: [Interval] = zones.enumerated().map { idx, zone in
            Interval(zone: zone, duration: 10, sortOrder: idx)
        }
        intervals.append(Interval(zone: .zone1, duration: 10, sortOrder: intervals.count))

        let workout = Workout(name: "🌈 Debug Rainbow", intervals: intervals)
        workout.id = id
        workout.sortOrder = -1  // pin to the top of the library
        context.insert(workout)
        try? context.save()
    }
#endif
}
