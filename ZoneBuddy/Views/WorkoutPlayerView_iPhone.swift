import SwiftUI
import FTMSKit

struct WorkoutPlayerView_iPhone: View {
    var viewModel: WorkoutPlayerViewModel
    let workoutName: String
    @Binding var showExitConfirmation: Bool
    let dismiss: DismissAction

    @State private var selectedPage = 0
    private let settings = SettingsManager.shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var isBikeConnected: Bool {
        viewModel.isConnectedToBike
    }

    /// Accent color: zone color used for text/icons on the dark background mode.
    private var accentColor: Color {
        viewModel.currentZoneColor
    }

    /// Foreground color adapts: white on dark mode, computed contrast on solid color mode.
    private var fgColor: Color {
        isBikeConnected ? .white : viewModel.currentForegroundColor
    }

    var body: some View {
        ZStack {
            // Background: solid zone color (no bike) or black + edge glow (bike connected)
            if isBikeConnected {
                Color.black.ignoresSafeArea()

                EdgeGlowView(
                    actualZone: viewModel.actualPowerZone,
                    targetZone: viewModel.currentInterval?.zone,
                    intensity: 1.0
                )
            } else {
                viewModel.currentZoneColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: viewModel.currentIntervalIndex)
            }

            if viewModel.isFinished {
                finishedOverlay
            } else {
                TabView(selection: $selectedPage) {
                    (isLandscape ? AnyView(landscapeActiveWorkoutPage) : AnyView(activeWorkoutPage))
                        .tag(0)

                    metricsPage
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
    }

    // MARK: - Page 1: Active Workout

    private var activeWorkoutPage: some View {
        VStack(spacing: 16) {
            Color.clear.frame(height: 44)

            Spacer()

            Text(viewModel.currentLabel)
                .font(.title)
                .fontWeight(.medium)
                .foregroundStyle(isBikeConnected ? accentColor : fgColor)

            if let zoneNumber = viewModel.currentZoneNumber {
                Text("\(zoneNumber)")
                    .font(.system(size: 200, weight: .bold, design: .rounded))
                    .foregroundStyle(isBikeConnected ? accentColor : fgColor)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "flame.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(isBikeConnected ? .orange : fgColor)
            }

            // Target watt range below zone number
            if let rangeDesc = viewModel.targetRangeDescription {
                Text(rangeDesc)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(fgColor.opacity(0.7))
            }

            if viewModel.showTimer {
                Text(viewModel.secondsRemaining.formattedDuration)
                    .font(.system(size: 60, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(fgColor)
                    .contentTransition(.numericText())
            }

            Spacer()

            // Power bar (only when bike connected — no value without power data)
            if isBikeConnected, settings.layoutPreferences.showPowerBar {
                PowerZoneBar(
                    ftp: viewModel.currentFTP,
                    targetZone: viewModel.currentInterval?.zone,
                    currentPower: viewModel.currentBikeData?.instantaneousPower,
                    compact: true
                )
                .padding(.horizontal, 24)
            }

            // Control buttons
            HStack(spacing: 24) {
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
                    if let zoneNumber = viewModel.currentZoneNumber {
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
                    Text(viewModel.currentLabel)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(isBikeConnected ? accentColor : fgColor)

                    if let rangeDesc = viewModel.targetRangeDescription {
                        Text(rangeDesc)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(fgColor.opacity(0.7))
                    }

                    Text(viewModel.secondsRemaining.formattedDuration)
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
                if isBikeConnected, settings.layoutPreferences.showPowerBar {
                    PowerZoneBar(
                        ftp: viewModel.currentFTP,
                        targetZone: viewModel.currentInterval?.zone,
                        currentPower: viewModel.currentBikeData?.instantaneousPower,
                        compact: true
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

                if settings.layoutPreferences.showZoneInfo {
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
                    if settings.layoutPreferences.showPower {
                        DataTile(isVisible: true) {
                            PowerMetricTile(
                                power: viewModel.currentBikeData?.instantaneousPower,
                                ftp: viewModel.currentFTP,
                                foregroundColor: fgColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showCadence {
                        DataTile(isVisible: true) {
                            CadenceTile(
                                cadence: viewModel.currentBikeData?.instantaneousCadence,
                                foregroundColor: fgColor
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
                                foregroundColor: fgColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showSpeed {
                        DataTile(isVisible: true) {
                            SpeedTile(
                                speed: viewModel.currentBikeData?.instantaneousSpeed,
                                foregroundColor: fgColor
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
                    if settings.layoutPreferences.showAvgPower {
                        DataTile(isVisible: true) {
                            AvgPowerTile(
                                avgPower: viewModel.currentAvgPower,
                                foregroundColor: fgColor
                            )
                        }
                    }
                    if settings.layoutPreferences.showOutput {
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

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(fgColor.opacity(selectedPage == 0 ? 1.0 : 0.3))
                .frame(width: 8, height: 8)
            Circle()
                .fill(fgColor.opacity(selectedPage == 1 ? 1.0 : 0.3))
                .frame(width: 8, height: 8)
        }
    }

    private var finishedOverlay: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(fgColor)

            Text("Workout Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(fgColor)

            Text("Total time: \(viewModel.totalElapsedSeconds.formattedDuration)")
                .font(.title2)
                .foregroundStyle(fgColor.opacity(0.7))

            if let summary = viewModel.workoutSummary {
                bikeSummarySection(summary)
            }

            Button("Done") {
                viewModel.endActivity()
                dismiss()
            }
            .font(.title3)
            .buttonStyle(.borderedProminent)
            .tint(fgColor)
            .foregroundStyle(isBikeConnected ? .black : viewModel.currentZoneColor)
            .padding(.top, 20)
        }
    }

    private func bikeSummarySection(_ summary: WorkoutSummary) -> some View {
        VStack(spacing: 12) {
            Divider()
                .background(fgColor.opacity(0.3))

            HStack(spacing: 24) {
                summaryItem(value: "\(summary.avgPower)", label: "Avg Power", unit: "W")
                summaryItem(value: summary.formattedDistance, label: "Distance", unit: summary.distanceUnit)
            }

            HStack(spacing: 24) {
                summaryItem(value: "\(summary.totalCalories)", label: "Calories", unit: "kcal")
                summaryItem(value: String(format: "%.0f", summary.totalOutputKJ), label: "Output", unit: "kJ")
            }

            if let avgHR = summary.avgHeartRate {
                HStack(spacing: 24) {
                    summaryItem(value: "\(avgHR)", label: "Avg HR", unit: "bpm")
                }
            }

            if !summary.zoneTimeBreakdown.isEmpty {
                Divider()
                    .background(fgColor.opacity(0.3))
                zoneSummarySection(summary.zoneTimeBreakdown, totalDuration: summary.duration)
            }
        }
        .foregroundStyle(fgColor)
    }

    private func zoneSummarySection(_ breakdown: [PowerZone: Int], totalDuration: Int) -> some View {
        VStack(spacing: 8) {
            Text("Zone Breakdown")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(fgColor.opacity(0.6))

            HStack(spacing: 4) {
                ForEach(PowerZone.allCases) { zone in
                    let seconds = breakdown[zone] ?? 0
                    if seconds > 0 {
                        let fraction = CGFloat(seconds) / CGFloat(max(totalDuration, 1))
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(zone.color)
                                .frame(height: 24 * max(fraction * 7, 0.15))
                            Text("Z\(zone.rawValue)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(fgColor.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 40)
        }
    }

    private func summaryItem(value: String, label: String, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
            }
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.5)
                .opacity(0.7)
        }
    }
}
