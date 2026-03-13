import SwiftUI
import WatchConnectivity

struct WorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirmation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let workoutName: String
    private let intervals: [Interval]
    private let transitionWarningDuration: Int

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
        self.intervals = intervals
        self.transitionWarningDuration = transitionWarningDuration
        let musicManager: MusicPlaybackManaging? = playlistID != nil ? MusicPlaybackManager() : nil
        let healthKit: HealthKitWorkoutRecording? = bikeManager?.isConnected == true ? LiveHealthKitWorkoutManager() : nil
        let hrStreamer: HeartRateStreaming? = WCSession.isSupported()
            ? WatchHeartRateRelay()
            : BLEHeartRateScanner()
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
            WorkoutConnectivityManager.shared.sendWorkoutStart(
                intervals: intervals,
                workoutName: workoutName,
                transitionWarningDuration: transitionWarningDuration
            )
            if WCSession.isSupported() {
                HRRelayService.shared.startAdvertising()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            WorkoutSessionManager.shared.activeViewModel = nil
            viewModel.stopBackgroundKeepAlive()
            WorkoutConnectivityManager.shared.sendWorkoutEnded()
            HRRelayService.shared.stopAdvertising()
        }
        .onChange(of: WorkoutConnectivityManager.shared.watchEndedWorkout) { _, ended in
            if ended {
                WorkoutConnectivityManager.shared.resetWatchEndedWorkout()
                viewModel.pause()
                viewModel.endActivity()
                dismiss()
            }
        }
        .onChange(of: WorkoutConnectivityManager.shared.latestWatchHeartRate) { _, bpm in
            if let bpm {
                HRRelayService.shared.sendHeartRate(bpm)
            }
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
