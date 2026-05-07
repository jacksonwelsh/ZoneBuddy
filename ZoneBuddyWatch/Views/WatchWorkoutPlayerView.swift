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
                        .toolbar(.hidden, for: .navigationBar)
                        .tag(0)
                    intervalOverviewView
                        .toolbar(.visible, for: .navigationBar)
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
            WatchHRBroadcaster.shared.sendWatchEnded()
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
        .onReceive(NotificationCenter.default.publisher(for: .watchReceivedDismiss)) { _ in
            viewModel.pause()
            viewModel.endActivity()
            viewModel.stopBackgroundKeepAlive()
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchReceivedPause)) { _ in
            guard viewModel.isRunning else { return }
            isHandlingRemoteAction = true
            viewModel.pause()
            isHandlingRemoteAction = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchReceivedResume)) { _ in
            guard !viewModel.isRunning else { return }
            isHandlingRemoteAction = true
            viewModel.resume()
            isHandlingRemoteAction = false
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

                // Transition banner — always in layout so nothing shifts
                WatchTransitionBannerView(
                    upcomingLabel: viewModel.upcomingLabel,
                    upcomingColor: viewModel.upcomingZoneColor
                )
                .opacity(viewModel.showTransitionBanner ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: viewModel.showTransitionBanner)

                if let zoneNum = viewModel.currentZoneNumber {
                    Text("\(zoneNum)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.currentZoneColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: zoneNum)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }

                if viewModel.showTimer {
                    // Timer centered; HR overlaid at bottom-leading so it doesn't shift centering
                    Text(viewModel.secondsRemaining.formattedDuration)
                        .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text(viewModel.currentHeartRate.map { "\($0)" } ?? "--")
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .foregroundStyle(.white)
                        }
                    WatchHeartRateBarView(
                        currentBPM: viewModel.currentHeartRate,
                        maxHR: viewModel.currentMaxHR,
                        showLabel: false
                    )
                } else {
                    WatchHeartRateBarView(
                        currentBPM: viewModel.currentHeartRate,
                        maxHR: viewModel.currentMaxHR
                    )
                }

                HStack(spacing: 12) {
                    Button(action: { showExitConfirm = true }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(.red.opacity(0.2), in: .circle)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        viewModel.togglePlayPause()
                        if !isHandlingRemoteAction {
                            if viewModel.isRunning {
                                WatchConnectivityManager.shared.sendWorkoutResumed()
                                WatchHRBroadcaster.shared.sendWatchResumed()
                            } else {
                                WatchConnectivityManager.shared.sendWorkoutPaused()
                                WatchHRBroadcaster.shared.sendWatchPaused()
                            }
                        }
                    }) {
                        Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.2), in: .circle)
                    }
                    .buttonStyle(.plain)
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
        let lastZoneColor = viewModel.intervals.last?.zone?.color ?? .green
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [lastZoneColor.opacity(0.4), lastZoneColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(lastZoneColor)
                    .symbolEffect(.bounce, options: .nonRepeating)
            }

            Text("Workout Complete")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)

            Text(viewModel.totalElapsedSeconds.formattedDuration)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(lastZoneColor)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(lastZoneColor)
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
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
