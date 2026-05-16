import SwiftUI
import FTMSKit

struct WorkoutPlayerView_iPhone: View {
    var viewModel: WorkoutPlayerViewModel
    let workoutName: String
    @Binding var showExitConfirmation: Bool
    let dismiss: DismissAction

    @State private var selectedPage = 0
    @State private var showTrainerSheet = false
    private let settings = SettingsManager.shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isTrainerControlAvailable: Bool {
        viewModel.isConnectedToBike
            && viewModel.trainerController?.capabilities?.powerTargetSettingSupported == true
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var isBikeConnected: Bool {
        viewModel.isConnectedToBike
    }

    private var isFTPTest: Bool { viewModel.isFTPTest }
    private var isFreeRide: Bool { viewModel.mode.isFreeRide }

    /// In FTP test mode, replace the zone-derived label with a phase label
    /// (Warmup / FTP Test / Cooldown). In Free Ride, show actual zone name
    /// when a power zone is detected from the bike; otherwise "Free Ride".
    private var displayLabel: String {
        switch viewModel.ftpTestKind {
        case .twentyMinute:
            return FTPTestProtocol.phaseLabel(forIndex: viewModel.currentIntervalIndex)
        case .ramp:
            return FTPRampTestProtocol.phaseLabel(forIndex: viewModel.currentIntervalIndex)
        case .none:
            break
        }
        if isFreeRide {
            if isBikeConnected, let zone = viewModel.actualPowerZone {
                return zone.zoneName
            }
            return "Free Ride"
        }
        return viewModel.currentLabel
    }

    /// In Free Ride, the large number reflects actual power zone when available.
    private var displayZoneNumber: Int? {
        if isFreeRide && isBikeConnected {
            return viewModel.actualPowerZone?.rawValue
        }
        return viewModel.currentZoneNumber
    }

    /// Accent color: zone color used for text/icons on the dark background mode.
    /// In Free Ride, prefer the actual zone color when the bike is connected.
    private var accentColor: Color {
        if isFreeRide, isBikeConnected, let zone = viewModel.actualPowerZone {
            return zone.color
        }
        return viewModel.currentZoneColor
    }

    /// Timer seconds shown in the active page — counts down for time goals,
    /// counts up otherwise.
    private var timerSeconds: Int {
        if case .freeRide(let goal) = viewModel.mode {
            if case .time = goal { return viewModel.secondsRemaining }
            return viewModel.totalElapsedSeconds
        }
        return viewModel.secondsRemaining
    }

    private var timerCaption: String {
        if case .freeRide(let goal) = viewModel.mode {
            if case .time = goal { return "Remaining" }
            return "Elapsed"
        }
        return "Remaining"
    }

    /// Foreground color adapts: white on dark mode, computed contrast on solid color mode.
    private var fgColor: Color {
        isBikeConnected ? .white : viewModel.currentForegroundColor
    }

    /// Gray foreground used for live metrics (Power, HR, Cadence, Speed) when paused.
    /// When not paused falls back to fgColor so callers need not branch.
    private var liveMetricColor: Color {
        viewModel.isPaused ? Color(white: 0.58) : fgColor
    }

    var body: some View {
        ZStack {
            if viewModel.isFinished {
                completionView
            } else {
                // Background: solid zone color (no bike) or black + edge glow (bike connected)
                if isBikeConnected {
                    Color.black.ignoresSafeArea()

                    if !isFTPTest {
                        EdgeGlowView(
                            actualZone: viewModel.actualPowerZone,
                            targetZone: viewModel.currentInterval?.zone,
                            intensity: 1.0
                        )
                    }
                } else {
                    viewModel.currentZoneColor
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.5), value: viewModel.currentIntervalIndex)
                }

                TabView(selection: $selectedPage) {
                    (isLandscape ? AnyView(landscapeActiveWorkoutPage) : AnyView(activeWorkoutPage))
                        .tag(0)

                    if isBikeConnected {
                        metricsPage
                            .tag(1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: isBikeConnected) { _, connected in
                    if !connected { selectedPage = 0 }
                }
            }

            // Transition banner — at the top, below the header
            VStack {
                if viewModel.showTransitionBanner {
                    TransitionBannerView(
                        upcomingLabel: viewModel.upcomingLabel,
                        upcomingColor: viewModel.upcomingZoneColor,
                        upcomingZoneNumber: viewModel.upcomingZoneNumber,
                        upcomingForegroundColor: viewModel.upcomingForegroundColor
                    )
                    .transition(.opacity)
                    .padding(.top, 64)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.showTransitionBanner)
            .allowsHitTesting(false)

            // Header overlay
            if !viewModel.isFinished {
                VStack {
                    HStack {
                        exitButton
                        Spacer()
                        if isTrainerControlAvailable {
                            trainerButton
                        }
                        pageIndicator
                    }
                    .overlay {
                        Text(workoutName)
                            .font(.title3)
                            .foregroundStyle(fgColor.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
            }
        }
        .onTapGesture {
            viewModel.showTimer.toggle()
        }
        .sheet(isPresented: $showTrainerSheet) {
            TrainerControlView(
                viewModel: viewModel,
                presentation: .sheet,
                onDismiss: { showTrainerSheet = false }
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: BLEHeartRateScanner.shared.watchTrainerAdjustDelta) { _, delta in
            guard let delta else { return }
            viewModel.applyTrainerAdjustment(deltaWatts: delta)
            BLEHeartRateScanner.shared.resetWatchTrainerAdjustDelta()
        }
    }

    private var trainerButton: some View {
        Button {
            showTrainerSheet = true
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(fgColor)
                .frame(width: 44, height: 44)
                .background(
                    isBikeConnected
                        ? Color.white.opacity(0.1)
                        : viewModel.currentZoneColor.opacity(0.6),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    // MARK: - Page 1: Active Workout

    private var activeWorkoutPage: some View {
        VStack(spacing: 16) {
            Color.clear.frame(height: 44)

            Spacer()

            Text(displayLabel)
                .font(.title)
                .fontWeight(.medium)
                .foregroundStyle(isBikeConnected ? accentColor : fgColor)

            if isFTPTest {
                Image(systemName: "stopwatch")
                    .font(.system(size: 120))
                    .foregroundStyle(isBikeConnected ? .white : fgColor)
                if let target = viewModel.rampStepTargetWatts {
                    Text("Target \(target) W")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(fgColor.opacity(0.85))
                        .contentTransition(.numericText())
                }
            } else if let zoneNumber = displayZoneNumber {
                Text("\(zoneNumber)")
                    .font(.system(size: 200, weight: .bold, design: .rounded))
                    .foregroundStyle(isBikeConnected ? accentColor : fgColor)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "flame.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(isBikeConnected ? .orange : fgColor)
            }

            // Target watt range below zone number — hidden in FTP test mode
            // (no FTP yet to compute zones from; showing watts would prime pacing).
            if !isFTPTest, !isFreeRide, let rangeDesc = viewModel.targetRangeDescription {
                Text(rangeDesc)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(fgColor.opacity(0.7))
            }

            if viewModel.showTimer {
                HStack(spacing: 12) {
                    Text(timerSeconds.formattedDuration)
                        .font(.system(size: 60, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(fgColor)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(timerCaption)
                        .font(.subheadline)
                        .foregroundStyle(fgColor.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Power bar (only when bike connected — no value without power data)
            // Always hidden in FTP test mode: no known FTP means no zones to render,
            // and showing live power biases first-time pacers (research-driven choice).
            if !isFTPTest, isBikeConnected, settings.layoutPreferences.showPowerBar {
                PowerZoneBar(
                    ftp: viewModel.currentFTP,
                    targetZone: isFreeRide ? nil : viewModel.currentInterval?.zone,
                    currentPower: viewModel.currentBikeData?.instantaneousPower,
                    compact: true,
                    isPaused: viewModel.isPaused
                )
                .padding(.horizontal, 24)
            }

            // Control buttons
            VStack(spacing: 8) {
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(fgColor)
                        .frame(width: 56, height: 56)
                        .background(
                            isBikeConnected
                                ? Color.white.opacity(0.1)
                                : viewModel.currentZoneColor.opacity(0.6),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)

                Button {
                    viewModel.audioCuesEnabled.toggle()
                } label: {
                    Image(systemName: viewModel.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(fgColor)
                        .frame(width: 56, height: 56)
                        .background(
                            isBikeConnected
                                ? Color.white.opacity(0.1)
                                : viewModel.currentZoneColor.opacity(0.6),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }

            // Music controls
            if settings.layoutPreferences.showMusicControls {
                MusicControlsView(
                    musicManager: viewModel.musicPlaybackManager,
                    foregroundColor: fgColor,
                    zoneColor: isBikeConnected ? Color.white.opacity(0.1) : viewModel.currentZoneColor,
                    compact: true
                )
            }

            Spacer().frame(height: 8)
        }
        .padding()
    }

    // MARK: - Landscape Active Page

    private var landscapeActiveWorkoutPage: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 36)

            // Two-column: big zone number left, zone info right
            HStack(alignment: .center, spacing: 24) {
                // Upper left: large zone number
                Group {
                    if isFTPTest {
                        VStack(spacing: 6) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 80))
                                .foregroundStyle(isBikeConnected ? .white : fgColor)
                            if let target = viewModel.rampStepTargetWatts {
                                Text("Target \(target) W")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundStyle(fgColor.opacity(0.85))
                                    .contentTransition(.numericText())
                            }
                        }
                    } else if let zoneNumber = displayZoneNumber {
                        Text("\(zoneNumber)")
                            .font(.system(size: 130, weight: .bold, design: .rounded))
                            .foregroundStyle(isBikeConnected ? accentColor : fgColor)
                            .contentTransition(.numericText())
                    } else {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(isBikeConnected ? .orange : fgColor)
                    }
                }
                .frame(maxWidth: .infinity)

                // Upper right: zone name + target watts + time remaining
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayLabel)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(isBikeConnected ? accentColor : fgColor)

                    if !isFTPTest, !isFreeRide, let rangeDesc = viewModel.targetRangeDescription {
                        Text(rangeDesc)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(fgColor.opacity(0.7))
                    }

                    Text(timerSeconds.formattedDuration)
                        .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(fgColor)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)

            // Bottom: power bar + controls
            VStack(spacing: 10) {
                if !isFTPTest, isBikeConnected, settings.layoutPreferences.showPowerBar {
                    PowerZoneBar(
                        ftp: viewModel.currentFTP,
                        targetZone: viewModel.currentInterval?.zone,
                        currentPower: viewModel.currentBikeData?.instantaneousPower,
                        compact: true,
                        isPaused: viewModel.isPaused
                    )
                    .padding(.horizontal, 24)
                }

                HStack(spacing: 20) {
                    Spacer()

                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(fgColor)
                            .frame(width: 44, height: 44)
                            .background(
                                isBikeConnected
                                    ? Color.white.opacity(0.1)
                                    : viewModel.currentZoneColor.opacity(0.6),
                                in: .circle
                            )
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    Button {
                        viewModel.audioCuesEnabled.toggle()
                    } label: {
                        Image(systemName: viewModel.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(fgColor)
                            .frame(width: 44, height: 44)
                            .background(
                                isBikeConnected
                                    ? Color.white.opacity(0.1)
                                    : viewModel.currentZoneColor.opacity(0.6),
                                in: .circle
                            )
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    if settings.layoutPreferences.showMusicControls {
                        MusicControlsView(
                            musicManager: viewModel.musicPlaybackManager,
                            foregroundColor: fgColor,
                            zoneColor: isBikeConnected ? Color.white.opacity(0.1) : viewModel.currentZoneColor,
                            compact: true
                        )
                    }

                    Spacer()
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Page 2: Metrics

    private var metricsPage: some View {
        ScrollView {
            VStack(spacing: 12) {
                Color.clear.frame(height: 56)

                if !isFTPTest, !isFreeRide, settings.layoutPreferences.showZoneInfo {
                    DataTile(isVisible: true) {
                        ZoneInfoTile(
                            zone: viewModel.currentInterval?.zone,
                            ftp: viewModel.currentFTP,
                            foregroundColor: fgColor
                        )
                    }
                }

                // Primary metrics row
                HStack(spacing: 12) {
                    if !isFTPTest, settings.layoutPreferences.showPower {
                        DataTile(isVisible: true) {
                            PowerMetricTile(
                                power: viewModel.currentBikeData?.instantaneousPower,
                                ftp: viewModel.currentFTP,
                                foregroundColor: liveMetricColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showCadence {
                        DataTile(isVisible: true) {
                            CadenceTile(
                                cadence: viewModel.currentBikeData?.instantaneousCadence,
                                foregroundColor: liveMetricColor
                            )
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Secondary metrics row
                HStack(spacing: 12) {
                    if settings.layoutPreferences.showHeartRate {
                        DataTile(isVisible: true) {
                            HeartRateTile(
                                heartRate: viewModel.currentHeartRate,
                                foregroundColor: liveMetricColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showSpeed {
                        DataTile(isVisible: true) {
                            SpeedTile(
                                speed: viewModel.currentBikeData?.instantaneousSpeed,
                                foregroundColor: liveMetricColor
                            )
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Tertiary row
                HStack(spacing: 12) {
                    if settings.layoutPreferences.showDistance {
                        DataTile(isVisible: true) {
                            DistanceTile(
                                distance: viewModel.computedDistanceMeters > 0 ? viewModel.computedDistanceMeters : nil,
                                foregroundColor: fgColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showCalories {
                        DataTile(isVisible: true) {
                            CaloriesTile(
                                calories: viewModel.currentTotalCalories,
                                foregroundColor: fgColor
                            )
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    if !isFTPTest, settings.layoutPreferences.showAvgPower {
                        DataTile(isVisible: true) {
                            AvgPowerTile(
                                avgPower: viewModel.currentAvgPower,
                                foregroundColor: fgColor
                            )
                        }
                    }
                    if !isFTPTest, settings.layoutPreferences.showOutput {
                        DataTile(isVisible: true) {
                            OutputTile(
                                outputKJ: viewModel.currentTotalOutputKJ,
                                foregroundColor: fgColor
                            )
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Next interval preview
                if let next = viewModel.nextInterval {
                    DataTile(isVisible: true) {
                        NextIntervalTile(
                            nextZone: next.zone,
                            nextLabel: viewModel.upcomingLabel,
                            nextDuration: next.duration,
                            foregroundColor: fgColor
                        )
                    }
                }

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Shared Components

    private var exitButton: some View {
        Button {
            showExitConfirmation = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(fgColor)
                .frame(width: 44, height: 44)
                .background(
                    isBikeConnected
                        ? Color.white.opacity(0.1)
                        : viewModel.currentZoneColor.opacity(0.6),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    @ViewBuilder
    private var pageIndicator: some View {
        if isBikeConnected {
            HStack(spacing: 6) {
                Circle()
                    .fill(fgColor.opacity(selectedPage == 0 ? 1.0 : 0.3))
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(fgColor.opacity(selectedPage == 1 ? 1.0 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var completionView: some View {
        if let kind = viewModel.ftpTestKind {
            FTPTestResultView(
                kind: kind,
                avgPower: viewModel.ftpTestAvgPower,
                bestMinutePower: viewModel.ftpTestBestMinutePower,
                computedFTP: viewModel.computedFTPFromTest,
                onDone: {
                    viewModel.endWorkout()
                    dismiss()
                }
            )
        } else if let session = viewModel.savedSession {
            WorkoutSessionDetailView(
                session: session,
                mode: .completion(onDone: {
                    viewModel.endWorkout()
                    dismiss()
                })
            )
        } else {
            // Fallback: session save failed but workout is finished
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Workout Complete")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(viewModel.totalElapsedSeconds.formattedDuration)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Button("Done") {
                    viewModel.endWorkout()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }
}
