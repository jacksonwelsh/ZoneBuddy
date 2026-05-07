import SwiftUI
import SwiftData
import FTMSKit

struct WorkoutPlayerView_iPad: View {
    var viewModel: WorkoutPlayerViewModel
    let workoutName: String
    @Binding var showExitConfirmation: Bool
    let dismiss: DismissAction

    private let settings = SettingsManager.shared

    @Environment(\.colorScheme) private var colorScheme

    private var isBikeConnected: Bool {
        viewModel.isConnectedToBike
    }

    /// Primary content color — white in dark mode, black in light mode.
    private var fg: Color { colorScheme == .dark ? .white : .black }

    /// Zone number label color — adapts via asset catalog for contrast on either background.
    private var currentZoneLabelColor: Color {
        viewModel.currentInterval?.zone?.labelColor ?? (colorScheme == .dark ? .white : .black)
    }

    /// Gray foreground used for live metrics (Power, HR, Cadence, Speed) when paused.
    /// Adapts to color scheme for proper contrast on both light and dark backgrounds.
    private var liveMetricColor: Color {
        guard viewModel.isPaused else { return fg }
        return colorScheme == .dark ? Color(white: 0.60) : Color(white: 0.38)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var totalWorkoutSecondsRemaining: Int {
        let futureSeconds = viewModel.intervals
            .dropFirst(viewModel.currentIntervalIndex + 1)
            .reduce(0) { $0 + $1.duration }
        return viewModel.secondsRemaining + futureSeconds
    }

    var body: some View {
        ZStack {
            if viewModel.isFinished {
                completionView
            } else {
                // Background: solid + edge glow (bike connected) or zone-tinted gradient (no bike)
                if isBikeConnected {
                    if colorScheme == .dark {
                        Color.black.ignoresSafeArea()
                    } else {
                        Color(.systemBackground).ignoresSafeArea()
                    }
                } else {
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [
                                viewModel.currentZoneColor.opacity(0.15),
                                Color.black.opacity(0.95),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.8), value: viewModel.currentIntervalIndex)
                    } else {
                        LinearGradient(
                            colors: [
                                viewModel.currentZoneColor.opacity(0.10),
                                Color(.systemBackground),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.8), value: viewModel.currentIntervalIndex)
                    }
                }

                ScrollView {
                    VStack(spacing: 16) {
                        headerRow
                        topSection
                        metricsGrid
                        bottomSection
                    }
                    .padding(20)
                }

                // Edge glow — same as iPhone, device corner radius auto-detected
                if isBikeConnected {
                    EdgeGlowView(
                        actualZone: viewModel.actualPowerZone,
                        targetZone: viewModel.currentInterval?.zone,
                        intensity: 1.0
                    )
                }
            }

            // Workout remaining — top-right corner overlay
            if !viewModel.isFinished {
                VStack {
                    HStack {
                        Spacer()
                        workoutRemainingBadge
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Workout Remaining Badge

    private var workoutRemainingBadge: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(totalWorkoutSecondsRemaining.formattedDuration)
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(fg)
                .contentTransition(.numericText())
            Text("remaining")
                .font(.caption2)
                .foregroundStyle(fg.opacity(0.5))
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button {
                showExitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(fg)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text(workoutName)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(fg.opacity(0.8))

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Top Section

    private var topSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 32) {
                // Zone display — no card, number left / name+range right, centered in half
                HStack(alignment: .center, spacing: 16) {
                    Group {
                        if let zoneNumber = viewModel.currentZoneNumber {
                            Text("\(zoneNumber)")
                                .font(.system(size: 80, weight: .bold, design: .rounded))
                                .foregroundStyle(currentZoneLabelColor)
                                .contentTransition(.numericText())
                        } else {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.orange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.currentLabel)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(fg)

                        if let rangeDesc = viewModel.targetRangeDescription {
                            Text(rangeDesc)
                                .font(.headline)
                                .foregroundStyle(fg.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Playback controls — centered between zone and timer
                HStack(spacing: 16) {
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(fg)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)

                    Button {
                        viewModel.audioCuesEnabled.toggle()
                    } label: {
                        Image(systemName: viewModel.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(fg)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }

                // Timer — no card
                TimerTile(
                    secondsRemaining: viewModel.secondsRemaining,
                    intervalDuration: viewModel.currentInterval?.duration ?? 0,
                    foregroundColor: fg
                )
                .frame(maxWidth: .infinity)
            }

            // Power bar spanning full width — no card
            if settings.layoutPreferences.showPowerBar {
                VStack(alignment: .leading, spacing: 6) {
                    Text("POWER")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(fg.opacity(0.6))
                        .tracking(1)

                    PowerZoneBar(
                        ftp: viewModel.currentFTP,
                        targetZone: viewModel.currentInterval?.zone,
                        currentPower: viewModel.currentBikeData?.instantaneousPower,
                        compact: false,
                        isPaused: viewModel.isPaused
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // HR zone bar — shown once any HR data is available, no card
            if viewModel.currentHeartRate != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEART RATE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(fg.opacity(0.6))
                        .tracking(1)

                    HeartRateZoneBar(
                        maxHR: viewModel.currentMaxHR,
                        currentBPM: viewModel.currentHeartRate,
                        averageBPM: viewModel.averageHeartRate,
                        compact: false,
                        isPaused: viewModel.isPaused
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Metrics Grid

    @ViewBuilder
    private var metricsGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            if settings.layoutPreferences.showPower {
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

            if settings.layoutPreferences.showHeartRate {
                DataTile(isVisible: true) {
                    HeartRateTile(
                        heartRate: viewModel.currentHeartRate,
                        foregroundColor: liveMetricColor,
                        averageBPM: viewModel.averageHeartRate
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

            if settings.layoutPreferences.showDistance {
                DataTile(isVisible: true) {
                    DistanceTile(
                        distance: viewModel.computedDistanceMeters > 0 ? viewModel.computedDistanceMeters : nil,
                        foregroundColor: fg
                    )
                }
            }

            if settings.layoutPreferences.showCalories {
                DataTile(isVisible: true) {
                    CaloriesTile(
                        calories: viewModel.currentTotalCalories,
                        foregroundColor: fg
                    )
                }
            }

            if settings.layoutPreferences.showAvgPower {
                DataTile(isVisible: true) {
                    AvgPowerTile(
                        avgPower: viewModel.currentAvgPower,
                        foregroundColor: fg
                    )
                }
            }

            if settings.layoutPreferences.showOutput {
                DataTile(isVisible: true) {
                    OutputTile(
                        outputKJ: viewModel.currentTotalOutputKJ,
                        foregroundColor: fg
                    )
                }
            }

            if let next = viewModel.nextInterval {
                DataTile(isVisible: true) {
                    NextIntervalTile(
                        nextZone: next.zone,
                        nextLabel: viewModel.upcomingLabel,
                        nextDuration: next.duration,
                        foregroundColor: fg
                    )
                }
            }
        }
    }

    // MARK: - Bottom Section

    @ViewBuilder
    private var bottomSection: some View {
        if settings.layoutPreferences.showMusicControls {
            DataTile(isVisible: true) {
                MusicControlsView(
                    musicManager: viewModel.musicPlaybackManager,
                    foregroundColor: fg,
                    zoneColor: viewModel.currentZoneColor,
                    compact: false
                )
            }
        }
    }

    // MARK: - Finished

    @ViewBuilder
    private var completionView: some View {
        if let session = viewModel.savedSession {
            NavigationStack {
                WorkoutSessionDetailView(
                    session: session,
                    mode: .completion(onDone: {
                        viewModel.endActivity()
                        dismiss()
                    })
                )
            }
        } else {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                Text("Workout Complete")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(viewModel.totalElapsedSeconds.formattedDuration)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Button("Done") {
                    viewModel.endActivity()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }
}

// MARK: - Preview Mocks

@Observable
private final class PreviewBikeManager: BikeConnecting {
    var isConnected: Bool = true
    var connectedBikeName: String? = "Stages SB20"
    var latestBikeData: BikeData? = BikeData(
        instantaneousSpeed: 32.5,
        instantaneousCadence: 85.0,
        instantaneousPower: 210,
        timestamp: Date()
    )
    var discoveredDevices: [FTMSDiscoveredDevice] = []
    var isScanning: Bool = false
    var accumulatedSamples: [BikeDataSample] = []
    var hasReceivedNonZeroMetric: Bool = true
    var isReconnecting: Bool = false
    func startScanning() {}
    func stopScanning() {}
    func connect(to device: FTMSDiscoveredDevice) {}
    func disconnect() {}
    func drainSamples() -> [BikeDataSample] { [] }
    func autoConnect(timeout: TimeInterval) {}
    func attemptReconnect() {}
}

private final class PreviewHeartRateStreamer: HeartRateStreaming {
    var latestHeartRate: Int? = 142
    func startMonitoring(from startDate: Date) {}
    func stopMonitoring() {}
}

// MARK: - Previews

private struct iPadWorkoutPreview: View {
    @Environment(\.dismiss) var dismiss

    private let container: ModelContainer
    private let vm: WorkoutPlayerViewModel
    private let workoutName: String

    init(
        workoutName: String,
        intervals: [Interval],
        bike: PreviewBikeManager? = PreviewBikeManager(),
        hr: PreviewHeartRateStreamer? = PreviewHeartRateStreamer()
    ) {
        let c = try! ModelContainer(for: Interval.self, Workout.self, configurations: .init(isStoredInMemoryOnly: true))
        intervals.forEach { c.mainContext.insert($0) }
        container = c
        vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: LiveTimerProvider(),
            workoutName: workoutName,
            bikeManager: bike,
            heartRateStreamer: hr
        )
        self.workoutName = workoutName
    }

    var body: some View {
        WorkoutPlayerView_iPad(
            viewModel: vm,
            workoutName: workoutName,
            showExitConfirmation: .constant(false),
            dismiss: dismiss
        )
        .modelContainer(container)
    }
}

#Preview("iPad Workout - Zone 3") {
    iPadWorkoutPreview(workoutName: "Power Zone Endurance", intervals: [
        Interval(zone: .zone1, duration: 300, sortOrder: 0),
        Interval(zone: .zone3, duration: 600, sortOrder: 1),
        Interval(zone: .zone4, duration: 300, sortOrder: 2),
        Interval(zone: .zone5, duration: 240, sortOrder: 3),
        Interval(zone: .zone2, duration: 300, sortOrder: 4),
    ])
}

#Preview("iPad Workout - Warmup") {
    iPadWorkoutPreview(workoutName: "Recovery Ride", intervals: [
        Interval.warmup(duration: 300, sortOrder: 0),
        Interval(zone: .zone3, duration: 600, sortOrder: 1),
        Interval(zone: .zone1, duration: 300, sortOrder: 2),
    ])
}

#Preview("iPad Workout - Watch HR, No Bike") {
    iPadWorkoutPreview(
        workoutName: "Power Zone Endurance",
        intervals: [
            Interval(zone: .zone1, duration: 300, sortOrder: 0),
            Interval(zone: .zone3, duration: 600, sortOrder: 1),
            Interval(zone: .zone4, duration: 300, sortOrder: 2),
        ],
        bike: nil,
        hr: PreviewHeartRateStreamer()
    )
}

#Preview("iPad Workout - No Connections") {
    iPadWorkoutPreview(
        workoutName: "Power Zone Endurance",
        intervals: [
            Interval(zone: .zone1, duration: 300, sortOrder: 0),
            Interval(zone: .zone3, duration: 600, sortOrder: 1),
            Interval(zone: .zone4, duration: 300, sortOrder: 2),
        ],
        bike: nil,
        hr: nil
    )
}
