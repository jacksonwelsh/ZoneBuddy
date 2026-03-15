import SwiftUI
import SwiftData

@main
struct ZoneBuddyWatchApp: App {
    init() {
        WatchConnectivityManager.shared.activate()
        WatchHRBroadcaster.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutLibraryView()
        }
        .modelContainer(DataStore.shared.container)
    }
}
