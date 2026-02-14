import Testing
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
        #expect(fetched.first?.intervals.count == 2)
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
