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
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback to local-only if CloudKit fails
            let fallback = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorkoutLibraryView()
        }
        .modelContainer(sharedModelContainer)
    }
}
