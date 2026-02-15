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
    init() {
        LiveSpeechCueProvider.warmUp()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workout.self,
            Interval.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorkoutLibraryView()
        }
        .modelContainer(sharedModelContainer)
    }
}
