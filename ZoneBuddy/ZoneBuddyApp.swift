//
//  ZoneBuddyApp.swift
//  ZoneBuddy
//
//  Created by Jackson Welsh on 2/13/26.
//

import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case workouts
    case history
    case settings
}

@main
struct ZoneBuddyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingImport: WorkoutTransferData?
    @State private var showOnboarding: Bool
    @State private var showFTPTestAfterOnboarding: Bool = false
    @State private var selectedTab: AppTab = .workouts
    @State private var importError: String?

    init() {
        LiveSpeechCueProvider.warmUp()
        // Honor the iOS Settings.app "Re-run Onboarding" toggle before any auto-connect work
        // so a user being re-onboarded isn't immediately greeted by an auto-reconnect spinner.
        SettingsManager.shared.consumeRerunFlagIfSet()
        _showOnboarding = State(initialValue: !SettingsManager.shared.hasCompletedOnboarding)
        if SettingsManager.shared.hasCompletedOnboarding {
            BikeManagerProvider.current.autoConnect(timeout: 8)
        }
        WorkoutConnectivityManager.shared.activate()
#if DEBUG
        DataStore.shared.seedRainbowWorkoutIfNeeded()
#endif
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Workouts", systemImage: "figure.indoor.cycle", value: AppTab.workouts) {
                    WorkoutLibraryView(pendingImport: $pendingImport)
                }
                Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                    WorkoutHistoryView()
                }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .onOpenURL { url in
                handleOpenURL(url)
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingFlowView { routeToFTPTest in
                    showOnboarding = false
                    if routeToFTPTest {
                        showFTPTestAfterOnboarding = true
                    } else {
                        // Onboarding finalized — kick off the auto-connect that we deferred.
                        BikeManagerProvider.current.autoConnect(timeout: 8)
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

    /// Routes an incoming URL. File URLs are GPX routes opened from the Files
    /// app / share sheet ("Open with ZoneBuddy"); everything else is a workout
    /// share link decoded by `WorkoutCoder`.
    private func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            importGPXFile(url)
        } else if let data = try? WorkoutCoder.decode(url) {
            pendingImport = data
        }
    }

    /// Imports a GPX file, then asks `WorkoutLibraryView` to show its preview.
    private func importGPXFile(_ url: URL) {
        do {
            let route = try RouteImporter.importRoute(from: url, into: DataStore.shared.context)
            // Surface the preview on the Workouts tab. Set the target before
            // switching tabs so a cold-launch library picks it up in `onAppear`.
            NavigationManager.shared.routeToPreview = route
            selectedTab = .workouts
        } catch let err as GPXParseError {
            importError = err.userFacingMessage
        } catch {
            importError = error.localizedDescription
        }
    }
}
