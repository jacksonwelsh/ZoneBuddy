import SwiftUI

/// Pre-test explainer shown when the user taps "Take FTP Test" in Settings.
/// Describes the protocol, then routes through `BikePromptSheet` (in required
/// mode) so the user must confirm a bike that's reporting non-zero metrics
/// before the workout starts.
///
/// When the connected trainer reports ERG / FTMS power-target capability, a
/// picker is shown so the rider can choose between the classic 20-min test
/// and the smart-trainer-native ramp test. With no trainer or a non-ERG
/// trainer (power meter only, regular stationary bike), the ramp option is
/// hidden — a ramp test relies on the trainer driving target watts, which a
/// non-controllable bike can't do.
struct FTPTestIntroView: View {
    var bikeManager: any BikeConnecting = BikeManagerProvider.current

    @State private var showingBikePrompt = false
    @State private var showingPlayer = false
    @State private var selectedKind: FTPTestKind = .twentyMinute
    @Environment(\.dismiss) private var dismiss

    private var supportsERG: Bool {
        bikeManager.trainerController?.capabilities?.powerTargetSettingSupported == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if supportsERG {
                    protocolPicker
                }
                protocolSection
                if selectedKind == .twentyMinute {
                    pacingSection
                    whyHiddenSection
                } else {
                    rampSection
                }
                bikeRequiredNotice
            }
            .padding(20)
        }
        .navigationTitle("FTP Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Default to the ramp test when an ERG-capable trainer is connected
            // — it's the literature consensus for smart-trainer FTP testing and
            // requires no pacing skill. Rider can still pick 20-min.
            if supportsERG {
                selectedKind = .ramp
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let bikeReady = bikeManager.isConnected && bikeManager.hasReceivedNonZeroMetric
                if bikeReady {
                    showingPlayer = true
                } else {
                    showingBikePrompt = true
                }
            } label: {
                Text("Begin Test")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingBikePrompt) {
            BikePromptSheet(
                bikeManager: bikeManager,
                requireBike: true,
                onStart: {
                    showingBikePrompt = false
                    showingPlayer = true
                }
            )
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            NavigationStack {
                WorkoutPlayerView(
                    intervals: selectedIntervals,
                    workoutName: selectedWorkoutName,
                    bikeManager: bikeManager,
                    ftpTestKind: selectedKind
                )
            }
            .onDisappear {
                // Dismiss the intro view too so user lands back on Settings.
                dismiss()
            }
        }
    }

    private var selectedIntervals: [Interval] {
        switch selectedKind {
        case .twentyMinute: return FTPTestProtocol.makeIntervals()
        case .ramp: return FTPRampTestProtocol.makeIntervals()
        }
    }

    private var selectedWorkoutName: String {
        switch selectedKind {
        case .twentyMinute: return FTPTestProtocol.workoutName
        case .ramp: return FTPRampTestProtocol.workoutName
        }
    }

    private var protocolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Test type")
            Picker("Test type", selection: $selectedKind) {
                Text("Ramp (smart trainer)").tag(FTPTestKind.ramp)
                Text("20-minute (classic)").tag(FTPTestKind.twentyMinute)
            }
            .pickerStyle(.segmented)
            Text(selectedKind == .ramp
                 ? "Trainer steps wattage up each minute until you can't hold it. No pacing skill required."
                 : "Sustained 20-minute effort. Self-paced — requires pacing experience.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var rampSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("How the ramp works")
            Text("Your trainer holds you at a target wattage that steps up by \(FTPRampTestProtocol.rampStepWatts) W every minute, starting at \(FTPRampTestProtocol.rampStartWatts) W. Spin at a comfortable cadence. When you can't hold cadence at the current step anymore, stop pedaling and tap End — FTP is calculated as 75% of your best 1-minute power.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "stopwatch")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Measure Your Threshold Power")
                .font(.title2.weight(.bold))
            Text("A 45-minute guided test that determines the highest power you can sustain. Your zones, training targets, and progress all build on this number.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var protocolSection: some View {
        switch selectedKind {
        case .twentyMinute:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("How it works")
                phaseRow(symbol: "figure.cooldown", title: "Warmup", duration: "15 min", detail: "Easy spinning, gradually building.")
                phaseRow(symbol: "bolt.fill", title: "FTP Test", duration: "20 min", detail: "Hard but sustainable. Pace by feel.")
                phaseRow(symbol: "wind", title: "Cooldown", duration: "10 min", detail: "Easy spin to recover.")
            }
        case .ramp:
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("How it works")
                phaseRow(symbol: "figure.cooldown", title: "Warmup", duration: "5 min", detail: "Easy spinning to get loose.")
                phaseRow(symbol: "bolt.fill", title: "Ramp", duration: "Until failure", detail: "Trainer steps watts up each minute. Spin until you can't.")
                phaseRow(symbol: "wind", title: "Cooldown", duration: "5 min", detail: "Easy spin to recover.")
            }
        }
    }

    private var pacingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Pacing tips")
            bullet("First 5 minutes: stay slightly conservative — adrenaline is high, don't blow up early.")
            bullet("Minutes 5–10: settle into a hard but sustainable effort.")
            bullet("Minutes 10–15: hold steady.")
            bullet("Last 5 minutes: empty the tank.")
        }
    }

    private var whyHiddenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Power is hidden")
            Text("During the test we hide your live wattage and zone bar. Without an FTP to anchor against, watching the number pushes most riders to start too hard and fade — the most common reason first tests come out low.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var bikeRequiredNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bike required")
                    .font(.subheadline.weight(.semibold))
                Text("A connected, pedaling bike is required to record power for the calculation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func phaseRow(symbol: String, title: String, duration: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(duration).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        FTPTestIntroView()
    }
}
