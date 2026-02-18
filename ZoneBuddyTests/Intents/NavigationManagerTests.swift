import Testing
import Foundation
import SwiftData
@testable import ZoneBuddy

@MainActor
struct NavigationManagerTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Workout.self, Interval.self, configurations: config)
    }

    private func resetSingleton() {
        NavigationManager.shared.shouldStartWorkout = false
        NavigationManager.shared.selectedWorkout = nil
    }

    @Test
    func startWorkoutSetsWorkoutAndFlag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Test Ride")
        context.insert(workout)
        try context.save()

        resetSingleton()
        NavigationManager.shared.startWorkout(workout)

        #expect(NavigationManager.shared.shouldStartWorkout == true)
        #expect(NavigationManager.shared.selectedWorkout?.name == "Test Ride")

        resetSingleton()
    }

    @Test
    func selectedWorkoutPersistsAfterFlagReset() throws {
        // Regression: the cold-launch fix reads selectedWorkout in onAppear *after*
        // clearing shouldStartWorkout. If clearing the flag also cleared the workout,
        // playerDestination() would receive nil and show a blank screen.
        let container = try makeContainer()
        let context = container.mainContext
        let workout = Workout(name: "Zone 3 Ride")
        context.insert(workout)
        try context.save()

        resetSingleton()
        NavigationManager.shared.startWorkout(workout)

        // Simulate what onAppear/onChange does: consume the flag, keep the workout
        NavigationManager.shared.shouldStartWorkout = false

        #expect(NavigationManager.shared.selectedWorkout != nil)
        #expect(NavigationManager.shared.selectedWorkout?.name == "Zone 3 Ride")

        resetSingleton()
    }
}
