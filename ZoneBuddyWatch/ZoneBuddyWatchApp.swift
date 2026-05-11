import SwiftUI
import SwiftData

@main
struct ZoneBuddyWatchApp: App {
    init() {
        WatchConnectivityManager.shared.activate()
        WatchHRBroadcaster.shared.start()
        #if DEBUG
        if SimulatorFakes.shared.isEnabled {
            WatchNavigationManager.shared.pendingWorkout = .fakeSample
            WatchNavigationManager.shared.shouldStartWorkout = true
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutLibraryView()
        }
        .modelContainer(DataStore.shared.container)
    }
}
