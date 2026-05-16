import SwiftUI

struct WatchWorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirm = false
    @State private var isHandlingRemoteAction = false
    @State private var crownAccumulator: Double = 0
    @FocusState private var crownFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let isRemote: Bool
    private let startedAt: Date?

    /// Crown detents per emitted ±N-watt adjustment. Tuned so a deliberate
    /// rotation produces clear single steps without flooding BLE writes.
    private static let wattsPerDetent: Int = 5

    private var isFreeRide: Bool { viewModel.mode.isFreeRide }

    private var displayLabel: String {
        if isFreeRide {
            if let zone = viewModel.actualPowerZone { return zone.zoneName }
            return "Free Ride"
        }
        return viewModel.currentLabel
    }

    private var displayZoneNumber: Int? {
        if isFreeRide { return viewModel.actualPowerZone?.rawValue }
        return viewModel.currentZoneNumber
    }

    private var displayZoneColor: Color {
        if isFreeRide, let zone = viewModel.actualPowerZone { return zone.color }
        return viewModel.currentZoneColor
    }

    private var timerSeconds: Int {
        if case .freeRide(let goal) = viewModel.mode {
            if case .time = goal { return viewModel.secondsRemaining }
            return viewModel.totalElapsedSeconds
        }
        return viewModel.secondsRemaining
    }

    init(workout: Workout) {
        self.isRemote = false
        self.startedAt = nil
        let (hk, hr): (HealthKitWorkoutRecording, HeartRateStreaming) = Self.makeManagers()
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: workout.sortedIntervals,
            timerProvider: LiveTimerProvider(),
            speechCueProvider: WatchSpeechCueProvider(),
            workoutName: workout.name,
            templateID: workout.id,
            transitionWarningDuration: workout.transitionWarningDuration,
            healthKitManager: hk,
            heartRateStreamer: hr,
            shouldPersistSession: true
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
        let mode: WorkoutMode
        if transferData.isFreeRide {
            let goal: FreeRideGoal?
            if let s = transferData.goalDurationSec {
                goal = .time(seconds: s)
            } else if let m = transferData.goalDistanceMeters {
                goal = .distance(meters: m)
            } else {
                goal = nil
            }
            mode = .freeRide(goal: goal)
        } else {
            mode = .scheduled
        }
        let (hk, hr): (HealthKitWorkoutRecording, HeartRateStreaming) = Self.makeManagers(saveOnEnd: false)
        _viewModel = State(initialValue: WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            speechCueProvider: WatchSpeechCueProvider(),
            workoutName: transferData.name,
            transitionWarningDuration: transferData.transitionWarningDuration,
            healthKitManager: hk,
            heartRateStreamer: hr,
            shouldPersistSession: false,
            mode: mode
        ))
    }

    private static func makeManagers(saveOnEnd: Bool = true) -> (HealthKitWorkoutRecording, HeartRateStreaming) {
        #if DEBUG
        if SimulatorFakes.shared.isEnabled {
            let fake = FakeWatchHealthKitManager()
            return (fake, fake)
        }
        #endif
        let live = WatchHealthKitManager()
        live.saveOnEnd = saveOnEnd
        return (live, live)
    }

    var body: some View {
        Group {
            if viewModel.isFinished {
                finishedView
            } else if isFreeRide {
                // No interval list to page to — show the single active page.
                activeZoneView
            } else {
                TabView {
                    activeZoneView
                    intervalOverviewView
                }
                .tabViewStyle(.page)
            }
        }
        .onAppear {
            let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            viewModel.start(atElapsedSeconds: elapsed)
            crownFocused = true
        }
        .onDisappear {
            viewModel.stopBackgroundKeepAlive()
            // Only signal the phone/iPad when the user ended this workout —
            // a natural completion will be reached on their own clock too,
            // and sending an end here races their completion view and dismisses it.
            if !viewModel.isFinished {
                WatchConnectivityManager.shared.sendWorkoutEnded()
                WatchHRBroadcaster.shared.sendWatchEnded()
            }
            if isRemote {
                WatchNavigationManager.shared.reset()
            }
        }
        .onChange(of: viewModel.currentHeartRate) { _, hr in
            if let hr {
                #if DEBUG
                guard !SimulatorFakes.shared.isEnabled else { return }
                #endif
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
            viewModel.endWorkout()
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
        activeZoneContent
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                $crownAccumulator,
                from: -10_000,
                through: 10_000,
                by: 1,
                sensitivity: .low,
                isContinuous: true
            )
            .onChange(of: crownAccumulator) { _, newValue in
                let step = Double(Self.wattsPerDetent)
                guard abs(newValue) >= step else { return }
                let detents = (newValue / step).rounded(.towardZero)
                let deltaWatts = Int16(detents) * Int16(Self.wattsPerDetent)
                WatchHRBroadcaster.shared.sendTrainerAdjust(deltaWatts: deltaWatts)
                WKInterfaceDevice.current().play(.click)
                crownAccumulator -= Double(detents) * step
            }
    }

    private var activeZoneContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            WatchEdgeGlowView(zoneColor: displayZoneColor)

            VStack(spacing: 6) {
                Text(displayLabel)
                    .font(.headline)
                    .foregroundStyle(.white)

                // Transition banner — always in layout so nothing shifts.
                // Not used in Free Ride (no interval transitions).
                WatchTransitionBannerView(
                    upcomingLabel: viewModel.upcomingLabel,
                    upcomingColor: viewModel.upcomingZoneColor
                )
                .opacity((!isFreeRide && viewModel.showTransitionBanner) ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: viewModel.showTransitionBanner)

                if let zoneNum = displayZoneNumber {
                    Text("\(zoneNum)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(displayZoneColor)
                        .contentTransition(.numericText())
                        .animation(.default, value: zoneNum)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }

                if viewModel.showTimer {
                    // Timer centered; HR overlaid at bottom-leading so it doesn't shift centering
                    Text(timerSeconds.formattedDuration)
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
                viewModel.endWorkout()
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
