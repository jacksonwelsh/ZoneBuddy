import SwiftUI

struct WatchWorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirm = false
    @State private var isHandlingRemoteAction = false
    @Environment(\.dismiss) private var dismiss

    private let isRemote: Bool
    private let startedAt: Date?

    init(workout: Workout) {
        self.isRemote = false
        self.startedAt = nil
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
        self.startedAt = transferData.startedAt
        let healthKitManager = WatchHealthKitManager()
        healthKitManager.saveOnEnd = false
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
            let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            viewModel.start(atElapsedSeconds: elapsed)
        }
        .onDisappear {
            viewModel.stopBackgroundKeepAlive()
            WatchConnectivityManager.shared.sendWorkoutEnded()
            if isRemote {
                WatchNavigationManager.shared.reset()
            }
        }
        .onChange(of: viewModel.currentHeartRate) { _, hr in
            if let hr {
                WatchConnectivityManager.shared.sendHeartRate(hr)
                WatchHRBroadcaster.shared.updateHeartRate(hr)
            }
        }
        .onChange(of: viewModel.currentIntervalIndex) { oldIndex, newIndex in
            guard newIndex != oldIndex else { return }
            WKInterfaceDevice.current().play(.notification)
        }
        .onChange(of: WatchNavigationManager.shared.shouldDismissWorkout) { _, shouldDismiss in
            if shouldDismiss {
                viewModel.pause()
                viewModel.endActivity()
                viewModel.stopBackgroundKeepAlive()
                dismiss()
            }
        }
        .onChange(of: WatchNavigationManager.shared.shouldPauseWorkout) { _, shouldPause in
            if shouldPause {
                WatchNavigationManager.shared.shouldPauseWorkout = false
                guard viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.pause()
                isHandlingRemoteAction = false
            }
        }
        .onChange(of: WatchNavigationManager.shared.shouldResumeWorkout) { _, shouldResume in
            if shouldResume {
                WatchNavigationManager.shared.shouldResumeWorkout = false
                guard !viewModel.isRunning else { return }
                isHandlingRemoteAction = true
                viewModel.resume()
                isHandlingRemoteAction = false
            }
        }
    }

    // MARK: - Active Zone Page

    private var activeZoneView: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            WatchEdgeGlowView(zoneColor: viewModel.currentZoneColor)

            VStack(spacing: 6) {
                Text(viewModel.currentLabel)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let zoneNum = viewModel.currentZoneNumber {
                    Text("\(zoneNum)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.default, value: zoneNum)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }

                if viewModel.showTimer {
                    Text(viewModel.secondsRemaining.formattedDuration)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.white)
                }

                if let hr = viewModel.currentHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("\(hr)")
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
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

                    Button(action: {
                        viewModel.togglePlayPause()
                        if !isHandlingRemoteAction {
                            if viewModel.isRunning {
                                WatchConnectivityManager.shared.sendWorkoutResumed()
                            } else {
                                WatchConnectivityManager.shared.sendWorkoutPaused()
                            }
                        }
                    }) {
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
                viewModel.endActivity()
                viewModel.stopBackgroundKeepAlive()
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
