import SwiftUI
import FTMSKit

struct WorkoutPlayerView_iPad: View {
    var viewModel: WorkoutPlayerViewModel
    let workoutName: String
    @Binding var showExitConfirmation: Bool
    let dismiss: DismissAction

    private let settings = SettingsManager.shared

    private var isBikeConnected: Bool {
        viewModel.isConnectedToBike
    }

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ZStack {
            // Background: solid black + edge glow (bike connected) or zone-tinted gradient (no bike)
            if isBikeConnected {
                Color.black.ignoresSafeArea()
            } else {
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
            }

            if viewModel.isFinished {
                finishedOverlay
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        headerRow
                        topSection
                        metricsGrid
                        bottomSection
                    }
                    .padding(20)
                }
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
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button {
                showExitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text(workoutName)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Top Section

    private var topSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Zone display tile
                DataTile(isVisible: true) {
                    VStack(spacing: 8) {
                        if let zoneNumber = viewModel.currentZoneNumber {
                            Text("\(zoneNumber)")
                                .font(.system(size: 80, weight: .bold, design: .rounded))
                                .foregroundStyle(viewModel.currentZoneColor)
                                .contentTransition(.numericText())
                        } else {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.orange)
                        }

                        Text(viewModel.currentLabel)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)

                        if let rangeDesc = viewModel.targetRangeDescription {
                            Text(rangeDesc)
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                // Timer tile
                DataTile(isVisible: true) {
                    TimerTile(
                        secondsRemaining: viewModel.secondsRemaining,
                        intervalDuration: viewModel.currentInterval?.duration ?? 0,
                        foregroundColor: .white
                    )
                }
            }

            // Power bar spanning full width
            if settings.layoutPreferences.showPowerBar {
                DataTile(isVisible: true) {
                    PowerZoneBar(
                        ftp: viewModel.currentFTP,
                        targetZone: viewModel.currentInterval?.zone,
                        currentPower: viewModel.currentBikeData?.instantaneousPower,
                        compact: false
                    )
                }
            }

            // HR zone bar — always shown on iPad when HR data is available
            if viewModel.currentHeartRate != nil {
                DataTile(isVisible: true) {
                    VStack(spacing: 4) {
                        HeartRateZoneBar(
                            maxHR: viewModel.currentMaxHR,
                            currentBPM: viewModel.currentHeartRate,
                            compact: false
                        )
                        HStack {
                            Text("HR Zones")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            if let bpm = viewModel.currentHeartRate {
                                Text("\(bpm) bpm")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
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
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showCadence {
                DataTile(isVisible: true) {
                    CadenceTile(
                        cadence: viewModel.currentBikeData?.instantaneousCadence,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showHeartRate {
                DataTile(isVisible: true) {
                    HeartRateTile(
                        heartRate: viewModel.currentHeartRate,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showSpeed {
                DataTile(isVisible: true) {
                    SpeedTile(
                        speed: viewModel.currentBikeData?.instantaneousSpeed,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showDistance {
                DataTile(isVisible: true) {
                    DistanceTile(
                        distance: viewModel.computedDistanceMeters > 0 ? viewModel.computedDistanceMeters : nil,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showCalories {
                DataTile(isVisible: true) {
                    CaloriesTile(
                        calories: viewModel.currentTotalCalories,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showAvgPower {
                DataTile(isVisible: true) {
                    AvgPowerTile(
                        avgPower: viewModel.currentAvgPower,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showOutput {
                DataTile(isVisible: true) {
                    OutputTile(
                        outputKJ: viewModel.currentTotalOutputKJ,
                        foregroundColor: .white
                    )
                }
            }

            if settings.layoutPreferences.showZoneInfo, let zone = viewModel.actualPowerZone {
                DataTile(isVisible: true) {
                    ZoneInfoTile(
                        zone: zone,
                        ftp: viewModel.currentFTP,
                        foregroundColor: .white
                    )
                }
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 16) {
            // Music controls
            if settings.layoutPreferences.showMusicControls {
                DataTile(isVisible: true) {
                    MusicControlsView(
                        musicManager: viewModel.musicPlaybackManager,
                        foregroundColor: .white,
                        zoneColor: viewModel.currentZoneColor,
                        compact: false
                    )
                }
            }

            // Next interval + playback controls
            HStack(spacing: 16) {
                // Next interval preview
                if let next = viewModel.nextInterval {
                    DataTile(isVisible: true) {
                        NextIntervalTile(
                            nextZone: next.zone,
                            nextLabel: viewModel.upcomingLabel,
                            nextDuration: next.duration,
                            foregroundColor: .white
                        )
                    }
                }

                // Playback controls
                DataTile(isVisible: true) {
                    HStack(spacing: 24) {
                        Spacer()
                        Button {
                            viewModel.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)

                        Button {
                            viewModel.audioCuesEnabled.toggle()
                        } label: {
                            Image(systemName: viewModel.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Finished

    private var finishedOverlay: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)

            Text("Workout Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Total time: \(viewModel.totalElapsedSeconds.formattedDuration)")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))

            if let summary = viewModel.workoutSummary {
                bikeSummarySection(summary)
            }

            Button("Done") {
                viewModel.endActivity()
                dismiss()
            }
            .font(.title3)
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.top, 20)
        }
    }

    private func bikeSummarySection(_ summary: WorkoutSummary) -> some View {
        VStack(spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.3))

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
                    .background(Color.white.opacity(0.3))
                zoneSummarySection(summary.zoneTimeBreakdown, totalDuration: summary.duration)
            }
        }
        .foregroundStyle(.white)
    }

    private func zoneSummarySection(_ breakdown: [PowerZone: Int], totalDuration: Int) -> some View {
        VStack(spacing: 8) {
            Text("Zone Breakdown")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))

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
                                .foregroundStyle(.white.opacity(0.5))
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
