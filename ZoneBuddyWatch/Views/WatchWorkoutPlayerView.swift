import SwiftUI

struct WatchWorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirm = false
    @State private var hrBroadcaster = WatchHRBroadcaster()
    @Environment(\.dismiss) private var dismiss

    private let isRemote: Bool
    private let elapsedSecondsAtStart: Int

    init(workout: Workout) {
        self.isRemote = false
        self.elapsedSecondsAtStart = 0
        let healthKitManager = WatchHealthKitManager()
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: workout.sortedIntervals,
            timerProvider: LiveTimerProvider(),
            activityManager: NoOpActivityManager(),
            speechCueProvider: WatchSpeechCueProvider(),
            workoutName: workout.name,
            transitionWarningDuration: workout.transitionWarningDuration,
            healthKitManager: healthKitManager,
            heartRateStreamer: healthKitManager
        ))
    }

    init(transferData: WorkoutTransferData) {
        self.isRemote = true
        let intervals = transferData.intervals.enumerated().map { index, data in
            Interval(
                zone: data.zone.flatMap { PowerZone(rawValue: $0) },
                duration: data.duration,
                sortOrder: index
            )
        }
        if let startedAt = transferData.startedAt {
            self.elapsedSecondsAtStart = max(0, Int(Date().timeIntervalSince(startedAt)))
        } else {
            self.elapsedSecondsAtStart = 0
        }
        let healthKitManager = WatchHealthKitManager()
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            activityManager: NoOpActivityManager(),
            speechCueProvider: WatchSpeechCueProvider(),
            workoutName: transferData.name,
            transitionWarningDuration: transferData.transitionWarningDuration,
            healthKitManager: healthKitManager,
            heartRateStreamer: healthKitManager
        ))
    }

    var body: some View {
        Group {
            if viewModel.isFinished {
                finishedView
            } else {
                TabView {
                    activeZoneView
                        .tag(0)
                    intervalOverviewView
                        .tag(1)
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            WatchWorkoutSessionManager.shared.startSession()
            viewModel.start(atElapsedSeconds: elapsedSecondsAtStart)
            hrBroadcaster.start()
        }
        .onDisappear {
            WatchWorkoutSessionManager.shared.endSession()
            viewModel.stopBackgroundKeepAlive()
            WatchConnectivityManager.shared.sendWorkoutEnded()
            hrBroadcaster.stop()
            if isRemote {
                WatchNavigationManager.shared.reset()
            }
        }
        .onChange(of: viewModel.currentHeartRate) { _, hr in
            if let hr {
                WatchConnectivityManager.shared.sendHeartRate(hr)
                hrBroadcaster.updateHeartRate(hr)
            }
        }
        .onChange(of: WatchNavigationManager.shared.shouldDismissWorkout) { _, shouldDismiss in
            if shouldDismiss {
                viewModel.pause()
                viewModel.stopBackgroundKeepAlive()
                WatchWorkoutSessionManager.shared.endSession()
                dismiss()
            }
        }
    }

    // MARK: - Active Zone Page

    private var activeZoneView: some View {
        ZStack {
            viewModel.currentZoneColor
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Text(viewModel.currentLabel)
                    .font(.headline)
                    .foregroundStyle(viewModel.currentForegroundColor)

                if let zoneNum = viewModel.currentZoneNumber {
                    Text("\(zoneNum)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.currentForegroundColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: zoneNum)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(viewModel.currentForegroundColor)
                }

                if viewModel.showTimer {
                    Text(viewModel.secondsRemaining.formattedDuration)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(viewModel.currentForegroundColor)
                }

                if let hr = viewModel.currentHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("\(hr)")
                    }
                    .font(.caption)
                    .foregroundStyle(viewModel.currentForegroundColor)
                }

                if viewModel.showTransitionBanner {
                    WatchTransitionBannerView(
                        upcomingLabel: viewModel.upcomingLabel,
                        upcomingColor: viewModel.upcomingZoneColor
                    )
                }

                HStack(spacing: 16) {
                    Button(action: { showExitConfirm = true }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .confirmationDialog("End Workout?", isPresented: $showExitConfirm) {
            Button("End Workout", role: .destructive) {
                viewModel.pause()
                viewModel.stopBackgroundKeepAlive()
                WatchWorkoutSessionManager.shared.endSession()
                dismiss()
            }
        }
    }

    // MARK: - Finished View

    private var finishedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Done!")
                .font(.title2.bold())

            Text(viewModel.totalElapsedSeconds.formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Interval Overview Page

    private var intervalOverviewView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(viewModel.intervals.enumerated()), id: \.offset) { index, interval in
                    let isLast = index == viewModel.intervals.count - 1
                    WatchIntervalRowView(
                        interval: interval,
                        index: index,
                        currentIndex: viewModel.currentIntervalIndex,
                        isCooldown: isLast && interval.zone == .zone1
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Intervals")
    }
}
