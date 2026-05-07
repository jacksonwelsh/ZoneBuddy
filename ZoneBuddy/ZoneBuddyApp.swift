//
//  ZoneBuddyApp.swift
//  ZoneBuddy
//
//  Created by Jackson Welsh on 2/13/26.
//

import SwiftUI
import SwiftData

@main
struct ZoneBuddyApp: App {
    @State private var pendingImport: WorkoutTransferData?

    init() {
        LiveSpeechCueProvider.warmUp()
        LiveBikeConnectionManager.shared.autoConnect()
        WorkoutConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Workouts", systemImage: "figure.indoor.cycle") {
                    WorkoutLibraryView(pendingImport: $pendingImport)
                }
                Tab("History", systemImage: "clock.arrow.circlepath") {
                    WorkoutHistoryView()
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView()
                }
            }
            .onOpenURL { url in
                guard let data = try? WorkoutCoder.decode(url) else { return }
                pendingImport = data
            }
        }
        .modelContainer(DataStore.shared.container)
    }
}
