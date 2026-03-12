import SwiftUI
import SwiftData

@main
struct ZoneBuddyWatchApp: App {
    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutLibraryView()
        }
        .modelContainer(DataStore.shared.container)
    }
}
