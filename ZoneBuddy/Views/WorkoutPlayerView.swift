import SwiftUI

struct WorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirmation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let workoutName: String

    init(
        intervals: [Interval],
        workoutName: String,
        transitionWarningDuration: Int = 10,
        playlistID: String? = nil,
        playlistKind: String? = nil,
        playlistShuffle: Bool = false,
        playlistRepeat: Bool = false,
        playlistAutoMix: Bool = false,
        bikeManager: BikeConnecting? = LiveBikeConnectionManager.shared
    ) {
        self.workoutName = workoutName
        let musicManager: MusicPlaybackManaging? = playlistID != nil ? MusicPlaybackManager() : nil
        let healthKit: HealthKitWorkoutRecording? = bikeManager?.isConnected == true ? LiveHealthKitWorkoutManager() : nil
        let hrStreamer: HeartRateStreaming? = LiveHeartRateStreamer()
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            workoutName: workoutName,
            transitionWarningDuration: transitionWarningDuration,
            musicPlaybackManager: musicManager,
            playlistID: playlistID,
            playlistKind: playlistKind,
            playlistShuffle: playlistShuffle,
            playlistRepeat: playlistRepeat,
            playlistAutoMix: playlistAutoMix,
            bikeManager: bikeManager,
            healthKitManager: healthKit,
            heartRateStreamer: hrStreamer
        ))
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                WorkoutPlayerView_iPad(
                    viewModel: viewModel,
                    workoutName: workoutName,
                    showExitConfirmation: $showExitConfirmation,
                    dismiss: dismiss
                )
            } else {
                WorkoutPlayerView_iPhone(
                    viewModel: viewModel,
                    workoutName: workoutName,
                    showExitConfirmation: $showExitConfirmation,
                    dismiss: dismiss
                )
            }
        }
        .confirmationDialog("End Workout?", isPresented: $showExitConfirmation, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) {
                viewModel.pause()
                viewModel.endActivity()
                dismiss()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            WorkoutSessionManager.shared.activeViewModel = viewModel
            viewModel.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            WorkoutSessionManager.shared.activeViewModel = nil
            viewModel.stopBackgroundKeepAlive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                if viewModel.isRunning {
                    viewModel.recalculateOnForeground()
                }
            case .background:
                UIApplication.shared.isIdleTimerDisabled = false
            case .inactive:
                UIApplication.shared.isIdleTimerDisabled = false
            @unknown default:
                break
            }
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutPlayerView(
            intervals: [
                Interval(zone: .zone2, duration: 15, sortOrder: 0),
                Interval(zone: .zone4, duration: 10, sortOrder: 1),
                Interval(zone: .zone1, duration: 10, sortOrder: 2),
            ],
            workoutName: "Preview Ride"
        )
    }
}
