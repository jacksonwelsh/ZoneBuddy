import Testing
import SwiftData
import SwiftUI
@testable import ZoneBuddy

@MainActor
struct WorkoutEditorViewModelTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Workout.self, Interval.self, configurations: config)
    }

    @Test
    func addInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone3, duration: 300)

        #expect(vm.intervals.count == 1)
        #expect(vm.intervals.first?.zone == .zone3)
        #expect(vm.intervals.first?.duration == 300)
    }

    @Test
    func addWarmup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addWarmup(duration: 600)

        #expect(vm.intervals.first?.isWarmup == true)
    }

    @Test
    func removeInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone2, duration: 60)
        vm.addInterval(zone: .zone4, duration: 120)

        vm.removeInterval(at: IndexSet(integer: 0))

        #expect(vm.intervals.count == 1)
        #expect(vm.intervals.first?.zone == .zone4)
        #expect(vm.intervals.first?.sortOrder == 0)
    }

    @Test
    func moveInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone2, duration: 60)
        vm.addInterval(zone: .zone4, duration: 120)
        vm.addInterval(zone: .zone6, duration: 90)

        vm.moveInterval(from: IndexSet(integer: 2), to: 0)

        #expect(vm.intervals[0].zone == .zone6)
        #expect(vm.intervals[0].sortOrder == 0)
        #expect(vm.intervals[1].zone == .zone2)
        #expect(vm.intervals[1].sortOrder == 1)
    }

    @Test
    func updateName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Old Name")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.workoutName = "New Name"
        vm.updateName()

        #expect(workout.name == "New Name")
    }

    @Test
    func totalDuration() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone2, duration: 300)
        vm.addInterval(zone: .zone4, duration: 120)

        #expect(vm.totalDuration == 420)
    }

    @Test
    func isPlayable() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        #expect(vm.isPlayable == false)

        vm.addInterval(zone: .zone3, duration: 60)
        #expect(vm.isPlayable == true)
    }

    @Test
    func cooldownDetection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone3, duration: 300)
        vm.addInterval(zone: .zone1, duration: 180)

        #expect(vm.isCooldown(vm.intervals[0]) == false)
        #expect(vm.isCooldown(vm.intervals[1]) == true)
    }

    @Test
    func updateInterval() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone2, duration: 120)

        let interval = vm.intervals[0]
        vm.updateInterval(interval, zone: .zone5, duration: 300)

        #expect(interval.zone == .zone5)
        #expect(interval.duration == 300)
    }

    @Test
    func updateIntervalToWarmup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test")
        context.insert(workout)

        let vm = WorkoutEditorViewModel(workout: workout, modelContext: context)
        vm.addInterval(zone: .zone3, duration: 180)

        let interval = vm.intervals[0]
        vm.updateInterval(interval, zone: nil, duration: 300)

        #expect(interval.isWarmup == true)
        #expect(interval.duration == 300)
    }
}
