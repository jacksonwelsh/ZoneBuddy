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
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingImport: WorkoutTransferData?
    @State private var showOnboarding: Bool
    @State private var showFTPTestAfterOnboarding: Bool = false

    init() {
        LiveSpeechCueProvider.warmUp()
        // Honor the iOS Settings.app "Re-run Onboarding" toggle before any auto-connect work
        // so a user being re-onboarded isn't immediately greeted by an auto-reconnect spinner.
        SettingsManager.shared.consumeRerunFlagIfSet()
        _showOnboarding = State(initialValue: !SettingsManager.shared.hasCompletedOnboarding)
        if SettingsManager.shared.hasCompletedOnboarding {
            LiveBikeConnectionManager.shared.autoConnect()
        }
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
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingFlowView { routeToFTPTest in
                    showOnboarding = false
                    if routeToFTPTest {
                        showFTPTestAfterOnboarding = true
                    } else {
                        // Onboarding finalized — kick off the auto-connect that we deferred.
                        LiveBikeConnectionManager.shared.autoConnect()
                    }
                }
            }
            .fullScreenCover(isPresented: $showFTPTestAfterOnboarding) {
                NavigationStack {
                    FTPTestIntroView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showFTPTestAfterOnboarding = false }
                            }
                        }
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                guard oldPhase != .active, newPhase == .active else { return }
                SettingsManager.shared.consumeRerunFlagIfSet()
                if !SettingsManager.shared.hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
        }
        .modelContainer(DataStore.shared.container)
    }
}
