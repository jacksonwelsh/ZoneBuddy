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
    }

    var body: some Scene {
        WindowGroup {
            WorkoutLibraryView(pendingImport: $pendingImport)
                .onOpenURL { url in
                    guard let data = try? WorkoutCoder.decode(url) else { return }
                    pendingImport = data
                }
        }
        .modelContainer(DataStore.shared.container)
    }
}
