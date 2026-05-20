import SwiftUI

struct WatchWorkoutPlayerView: View {
    @State private var viewModel: WorkoutPlayerViewModel
    @State private var showExitConfirm = false
    @State private var isHandlingRemoteAction = false
    /// Which trainer control the Crown is currently driving. Derived live from the
    /// iPad's published state — when the iPad switches mode, the Watch follows.
    private enum AdjustMode {
        case targetWatts
        case resistanceLevel
    }

    @State private var crownAccumulator: Double = 0
    /// Absolute value the rider is dialing in (watts or level depending on mode).
    /// `nil` between rotation sessions — first Crown tick seeds it from the iPad's
    /// published value for the active mode.
    @State private var pendingValue: Int?
    /// Snapshot of the iPad's published value taken on the first tick of a session.
    @State private var baselineValue: Int?
    /// Units moved in the current direction since the last reversal. Once it crosses
    /// the mode's acceleration threshold, the per-detent step jumps up. Resets on
    /// direction reversal so corrections stay fine.
    @State private var sameDirectionAccumulated: Int = 0
    /// Sign of the most recent detent (+1 / -1 / 0). Used for the overlay arrow
    /// and for detecting direction reversals (which reset acceleration).
    @State private var lastAdjustDirection: Int = 0
    @State private var showAdjustOverlay: Bool = false
    /// Single task that debounces the BLE write + overlay fade. Re-armed on every
    /// detent so continued rotation keeps the commit pending; the user can correct
    /// the target by spinning the other way before this fires.
    @State private var commitTask: Task<Void, Never>? = nil
    @FocusState private var crownFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let isRemote: Bool
    private let startedAt: Date?

    /// ERG: 1W base step, 5W after 25W in one direction.
    /// Level: 1 base step, no acceleration (resistance ranges are tiny).
    private static let baseStepWatts: Int = 1
    private static let acceleratedStepWatts: Int = 5
    private static let accelerationThresholdWatts: Int = 25
    private static let resistanceStep: Int = 1

    /// Inactivity period after the last detent before the pending value is sent to
    /// the iPad. Long enough for the rider to keep rotating or reverse to correct.
    private static let commitDelay: Duration = .seconds(1)
    /// How long the overlay lingers after a commit so the rider sees the final value
    /// confirmed before it fades.
    private static let overlayHoldAfterCommit: Duration = .milliseconds(400)

    /// Trainer mode the iPad is currently in, derived from which value it most recently
    /// published as non-sentinel. The Watch follows iPad mode live — when the iPad
    /// switches Level↔ERG, the Crown's control scheme switches with it.
    private var activeMode: AdjustMode {
        WatchHRBroadcaster.shared.currentTrainerResistance != nil
            ? .resistanceLevel
            : .targetWatts
    }

    /// `.low` for Level (small range, want fine control), `.medium` for ERG.
    private var crownSensitivity: DigitalCrownRotationalSensitivity {
        activeMode == .resistanceLevel ? .low : .medium
    }

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
        .overlay {
            if showAdjustOverlay, let value = pendingValue {
                let mode = activeMode
                WatchTrainerAdjustOverlay(
                    value: value,
                    valueSuffix: mode == .targetWatts ? "W" : "",
                    caption: mode == .targetWatts ? "TARGET WATTS" : "RESISTANCE LEVEL",
                    direction: lastAdjustDirection,
                    zoneColor: displayZoneColor
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAdjustOverlay)
        .animation(.default, value: pendingValue)
        .onAppear {
            let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            viewModel.start(atElapsedSeconds: elapsed)
            crownFocused = true
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
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
        .onChange(of: activeMode) { _, _ in
            // The iPad switched ERG↔Level. Abandon any in-flight adjustment — the
            // rider's intent was for the previous mode and doesn't carry over.
            // The next Crown tick will start a fresh session under the new mode,
            // re-seeded from the iPad's current value.
            commitTask?.cancel()
            commitTask = nil
            resetSessionState()
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
                sensitivity: crownSensitivity,
                isContinuous: true
            )
            .onChange(of: crownAccumulator) { _, newValue in
                handleCrownChange(newValue)
            }
    }

    private func handleCrownChange(_ newValue: Double) {
        let mode = activeMode
        let step = currentStep(for: mode)
        let stepD = Double(step)
        guard abs(newValue) >= stepD else { return }

        let detents = (newValue / stepD).rounded(.towardZero)
        let deltaUnits = Int(detents) * step
        crownAccumulator -= Double(detents) * stepD
        guard deltaUnits != 0 else { return }

        let direction = deltaUnits > 0 ? 1 : -1
        if direction != lastAdjustDirection {
            sameDirectionAccumulated = 0
        }
        sameDirectionAccumulated += abs(deltaUnits)
        lastAdjustDirection = direction

        if baselineValue == nil {
            baselineValue = sessionBaseline(for: mode)
        }
        let baseline = baselineValue ?? 0
        let current = pendingValue ?? baseline
        let unclamped = current + deltaUnits
        let clamped = clampToBounds(unclamped, mode: mode)
        pendingValue = clamped

        // If the bound is in the way, drain the residual accumulator so the rider
        // can immediately come back by spinning the other way — otherwise they'd
        // have to "unwind" the wasted rotation before any change is visible.
        if clamped != unclamped {
            crownAccumulator = 0
        }

        WKInterfaceDevice.current().play(.click)
        showAdjustOverlay = true
        scheduleCommit()
    }

    private func clampToBounds(_ value: Int, mode: AdjustMode) -> Int {
        switch mode {
        case .targetWatts:
            // No bounds published for ERG — the iPad clamps to the bike's power range
            // server-side. We still hard-floor at 0 since negative watts are meaningless.
            return max(0, value)
        case .resistanceLevel:
            let lo = WatchHRBroadcaster.shared.trainerResistanceMin ?? 0
            let hi = WatchHRBroadcaster.shared.trainerResistanceMax ?? Int.max
            return Swift.min(Swift.max(value, lo), hi)
        }
    }

    private func currentStep(for mode: AdjustMode) -> Int {
        switch mode {
        case .targetWatts:
            return sameDirectionAccumulated >= Self.accelerationThresholdWatts
                ? Self.acceleratedStepWatts
                : Self.baseStepWatts
        case .resistanceLevel:
            // Resistance ranges are small (typically 0–30), so per-detent step stays
            // at 1 and the rider gets the fine control they'd get from the iPad's
            // own ± button.
            return Self.resistanceStep
        }
    }

    private func sessionBaseline(for mode: AdjustMode) -> Int {
        switch mode {
        case .targetWatts:
            return WatchHRBroadcaster.shared.currentTrainerTarget ?? 0
        case .resistanceLevel:
            return WatchHRBroadcaster.shared.currentTrainerResistance ?? 0
        }
    }

    /// Debounced commit: after `commitDelay` of no Crown movement, send the final
    /// pending value to the iPad on the channel matching the current iPad mode,
    /// hold the overlay briefly so the rider sees the confirmed value, then fade.
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: Self.commitDelay)
            if Task.isCancelled { return }
            if let value = pendingValue {
                switch activeMode {
                case .targetWatts:
                    WatchHRBroadcaster.shared.sendTrainerTarget(value)
                case .resistanceLevel:
                    WatchHRBroadcaster.shared.sendTrainerResistance(value)
                }
            }
            try? await Task.sleep(for: Self.overlayHoldAfterCommit)
            if Task.isCancelled { return }
            resetSessionState()
        }
    }

    /// Drop in-flight rotation session — used by both the post-commit cleanup and the
    /// iPad-mode-change handler. The latter abandons any pending value because the
    /// rider's intent was for the OLD mode, and that intent doesn't translate.
    private func resetSessionState() {
        showAdjustOverlay = false
        pendingValue = nil
        baselineValue = nil
        sameDirectionAccumulated = 0
        lastAdjustDirection = 0
        crownAccumulator = 0
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
