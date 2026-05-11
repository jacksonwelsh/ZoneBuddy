import SwiftUI
import WatchConnectivity

/// True when running inside Xcode's SwiftUI preview host (PreviewShell).
/// Used to skip live BLE/HealthKit/ActivityKit/audio side effects that crash the preview process.
var isXcodePreview: Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

struct WorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirmation = false
    @State private var isHandlingRemoteAction = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let workoutName: String
    private let intervals: [Interval]
    private let transitionWarningDuration: Int

    init(
        intervals: [Interval],
        workoutName: String,
        templateID: UUID? = nil,
        transitionWarningDuration: Int = 10,
        playlistID: String? = nil,
        playlistKind: String? = nil,
        playlistShuffle: Bool = false,
        playlistRepeat: Bool = false,
        playlistAutoMix: Bool = false,
        bikeManager: BikeConnecting? = nil,
        ftpTestIntervalIndex: Int? = nil
    ) {
        self.workoutName = workoutName
        self.intervals = intervals
        self.transitionWarningDuration = transitionWarningDuration

        if isXcodePreview {
            _viewModel = State(initialValue: WorkoutPlayerViewModel(
                intervals: intervals,
                timerProvider: LiveTimerProvider(),
                workoutName: workoutName,
                templateID: templateID,
                transitionWarningDuration: transitionWarningDuration,
                ftpTestIntervalIndex: ftpTestIntervalIndex
            ))
            return
        }

        let resolvedBike = bikeManager ?? BikeManagerProvider.current
        let musicManager: MusicPlaybackManaging? = playlistID != nil ? MusicPlaybackManager() : nil
        let hrStreamer: HeartRateStreaming? = HeartRateStreamerProvider.makeFakeIfEnabled()
            ?? (WCSession.isSupported() ? WatchHeartRateRelay() : BLEHeartRateScanner.shared)
        let hasBike = resolvedBike.isConnected
        let healthKit: HealthKitWorkoutRecording? = (hasBike || hrStreamer != nil) ? HealthKitWorkoutProvider.make() : nil
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            speechCueProvider: LiveSpeechCueProvider.shared,
            workoutName: workoutName,
            templateID: templateID,
            transitionWarningDuration: transitionWarningDuration,
            musicPlaybackManager: musicManager,
            playlistID: playlistID,
            playlistKind: playlistKind,
            playlistShuffle: playlistShuffle,
            playlistRepeat: playlistRepeat,
            playlistAutoMix: playlistAutoMix,
            bikeManager: resolvedBike,
            healthKitManager: healthKit,
            heartRateStreamer: hrStreamer,
            ftpTestIntervalIndex: ftpTestIntervalIndex
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
                if !WCSession.isSupported() {
                    BLEHeartRateScanner.shared.sendEndCommand()
                }
                viewModel.pause()
                viewModel.endWorkout()
                dismiss()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(viewModel.isFinished ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            if isXcodePreview { return }
            UIApplication.shared.isIdleTimerDisabled = true
            WorkoutSessionManager.shared.activeViewModel = viewModel
            viewModel.start()
            if WCSession.isSupported() {
                WorkoutConnectivityManager.shared.sendWorkoutStart(
                    intervals: intervals,
                    workoutName: workoutName,
                    transitionWarningDuration: transitionWarningDuration
                )
                HRRelayService.shared.startAdvertising()
            } else {
                // iPad: sync workout to Watch over BLE
                let transferIntervals = intervals.map {
                    IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
                }
                let transferData = WorkoutTransferData(
                    name: workoutName,
                    transitionWarningDuration: transitionWarningDuration,
                    intervals: transferIntervals,
                    startedAt: Date()
                )
                BLEHeartRateScanner.shared.sendWorkoutStart(transferData)
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            WorkoutSessionManager.shared.activeViewModel = nil
            viewModel.stopBackgroundKeepAlive()
            if WCSession.isSupported() {
                WorkoutConnectivityManager.shared.sendWorkoutEnded()
                HRRelayService.shared.stopAdvertising()
            } else {
                BLEHeartRateScanner.shared.sendEndCommand()
            }
        }
        .onChange(of: WorkoutConnectivityManager.shared.watchEndedWorkout) { _, ended in
            if ended {
                WorkoutConnectivityManager.shared.resetWatchEndedWorkout()
                // If we already completed naturally, keep the completion view visible
                // for the user to dismiss manually.
                guard !viewModel.isFinished else { return }
                viewModel.pause()
                viewModel.endWorkout()
                dismiss()
            }
        }
        .onChange(of: WorkoutConnectivityManager.shared.latestWatchHeartRate) { _, bpm in
            if let bpm {
                HRRelayService.shared.sendHeartRate(bpm)
            }
        }
        .onChange(of: WorkoutConnectivityManager.shared.watchPausedWorkout) { _, paused in
            if paused {
                WorkoutConnectivityManager.shared.resetWatchPausedWorkout()
                guard viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.pause()
                isHandlingRemoteAction = false
            }
        }
        .onChange(of: WorkoutConnectivityManager.shared.watchResumedWorkout) { _, resumed in
            if resumed {
                WorkoutConnectivityManager.shared.resetWatchResumedWorkout()
                guard !viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.resume()
                isHandlingRemoteAction = false
            }
        }
        // BLE Watch→iPad commands (iPad only — WCSession not supported on iPad)
        .onChange(of: BLEHeartRateScanner.shared.watchEndedWorkout) { _, ended in
            if ended {
                BLEHeartRateScanner.shared.resetWatchEndedWorkout()
                guard !viewModel.isFinished else { return }
                viewModel.pause()
                viewModel.endWorkout()
                dismiss()
            }
        }
        .onChange(of: BLEHeartRateScanner.shared.watchPausedWorkout) { _, paused in
            if paused {
                BLEHeartRateScanner.shared.resetWatchPausedWorkout()
                guard viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.pause()
                isHandlingRemoteAction = false
            }
        }
        .onChange(of: BLEHeartRateScanner.shared.watchResumedWorkout) { _, resumed in
            if resumed {
                BLEHeartRateScanner.shared.resetWatchResumedWorkout()
                guard !viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.resume()
                isHandlingRemoteAction = false
            }
        }
        .onChange(of: viewModel.isRunning) { oldValue, newValue in
            guard !isHandlingRemoteAction else { return }
            if oldValue && !newValue && !viewModel.isFinished {
                if WCSession.isSupported() {
                    WorkoutConnectivityManager.shared.sendWorkoutPaused()
                } else {
                    BLEHeartRateScanner.shared.sendPauseCommand()
                }
            } else if !oldValue && newValue {
                if WCSession.isSupported() {
                    WorkoutConnectivityManager.shared.sendWorkoutResumed()
                } else {
                    BLEHeartRateScanner.shared.sendResumeCommand()
                }
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
