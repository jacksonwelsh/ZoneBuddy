import Testing
import Foundation
import SwiftData
@testable import ZoneBuddy

@MainActor
struct WorkoutTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Workout.self, Interval.self, configurations: config)
    }

    @Test
    func createWorkout() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let workout = Workout(name: "Test Ride")
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Test Ride")
        #expect(fetched.first?.transitionWarningDuration == 10)
    }

    @Test
    func customTransitionWarning() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let workout = Workout(name: "Test", transitionWarningDuration: 5)
        context.insert(workout)
        try context.save()

        #expect(workout.transitionWarningDuration == 5)
    }

    @Test
    func workoutWithIntervals() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let interval1 = Interval(zone: .zone3, duration: 300, sortOrder: 0)
        let interval2 = Interval(zone: .zone5, duration: 120, sortOrder: 1)
        let workout = Workout(name: "PZ Max", intervals: [interval1, interval2])
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        #expect(fetched.first?.intervals?.count == 2)
        #expect(fetched.first?.totalDuration == 420)
    }

    @Test
    func sortedIntervals() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let i1 = Interval(zone: .zone2, duration: 60, sortOrder: 2)
        let i2 = Interval(zone: .zone4, duration: 90, sortOrder: 0)
        let i3 = Interval(zone: .zone1, duration: 120, sortOrder: 1)
        let workout = Workout(name: "Test", intervals: [i1, i2, i3])
        context.insert(workout)
        try context.save()

        let sorted = workout.sortedIntervals
        #expect(sorted[0].zone == .zone4)
        #expect(sorted[1].zone == .zone1)
        #expect(sorted[2].zone == .zone2)
    }

    @Test
    func cooldownDetection() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let i1 = Interval(zone: .zone3, duration: 300, sortOrder: 0)
        let i2 = Interval(zone: .zone1, duration: 300, sortOrder: 1)
        let workout = Workout(name: "Test", intervals: [i1, i2])
        context.insert(workout)
        try context.save()

        #expect(workout.isCooldown(i1) == false)
        #expect(workout.isCooldown(i2) == true)
    }

    @Test
    func nonZone1LastIsNotCooldown() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let i1 = Interval(zone: .zone3, duration: 300, sortOrder: 0)
        let i2 = Interval(zone: .zone5, duration: 300, sortOrder: 1)
        let workout = Workout(name: "Test", intervals: [i1, i2])
        context.insert(workout)
        try context.save()

        #expect(workout.isCooldown(i2) == false)
    }

    // MARK: - id (regression: intern added UUID field)

    @Test
    func workoutHasUniqueId() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let w1 = Workout(name: "Ride A")
        let w2 = Workout(name: "Ride B")
        context.insert(w1)
        context.insert(w2)
        try context.save()

        #expect(w1.id != w2.id)
    }

    @Test
    func workoutIdIsStableAfterPersistAndRefetch() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let workout = Workout(name: "Stable Ride")
        context.insert(workout)
        try context.save()
        let originalId = workout.id

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        #expect(fetched.first?.id == originalId)
    }

    // MARK: - Sort order fetch (regression: DataStore was sorting by createdAt)

    @Test
    func fetchDescriptorSortsBySortOrderAscending() throws {
        // Regression: DataStore.fetchWorkouts() was sorting by createdAt descending,
        // which disagrees with the user-defined order shown in the app.
        let container = try makeContainer()
        let context = container.mainContext

        // Insert intentionally out of sortOrder sequence to prove the descriptor wins
        let w3 = Workout(name: "Third")
        w3.sortOrder = 2
        let w1 = Workout(name: "First")
        w1.sortOrder = 0
        let w2 = Workout(name: "Second")
        w2.sortOrder = 1
        context.insert(w3)
        context.insert(w1)
        context.insert(w2)
        try context.save()

        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 3)
        #expect(fetched[0].name == "First")
        #expect(fetched[1].name == "Second")
        #expect(fetched[2].name == "Third")
    }

    @Test
    func sortOrderDefaultsToZero() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let workout = Workout(name: "Test")
        context.insert(workout)
        try context.save()

        #expect(workout.sortOrder == 0)
    }

    @Test
    func sortOrderPersists() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let w1 = Workout(name: "First")
        w1.sortOrder = 0
        let w2 = Workout(name: "Second")
        w2.sortOrder = 1
        context.insert(w1)
        context.insert(w2)
        try context.save()

        let descriptor = FetchDescriptor<Workout>(sortBy: [.init(\Workout.sortOrder)])
        let fetched = try context.fetch(descriptor)
        #expect(fetched[0].name == "First")
        #expect(fetched[1].name == "Second")
    }

    @Test
    func cascadeDelete() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let interval = Interval(zone: .zone2, duration: 60, sortOrder: 0)
        let workout = Workout(name: "Test", intervals: [interval])
        context.insert(workout)
        try context.save()

        context.delete(workout)
        try context.save()

        let intervals = try context.fetch(FetchDescriptor<Interval>())
        #expect(intervals.isEmpty)
    }
}
