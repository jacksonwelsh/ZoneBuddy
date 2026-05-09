import SwiftUI

/// Pre-test explainer shown when the user taps "Take FTP Test" in Settings.
/// Describes the 45-minute protocol, then routes through `BikePromptSheet` (in required
/// mode) so the user must confirm a bike that's reporting non-zero metrics before the
/// workout starts.
struct FTPTestIntroView: View {
    var bikeManager: BikeConnecting = LiveBikeConnectionManager.shared

    @State private var showingBikePrompt = false
    @State private var showingPlayer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                protocolSection
                pacingSection
                whyHiddenSection
                bikeRequiredNotice
            }
            .padding(20)
        }
        .navigationTitle("FTP Test")
        .navigationBarTitleDisplayMode(.inline)
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
                    intervals: FTPTestProtocol.makeIntervals(),
                    workoutName: FTPTestProtocol.workoutName,
                    bikeManager: bikeManager,
                    ftpTestIntervalIndex: FTPTestProtocol.testIntervalIndex
                )
            }
            .onDisappear {
                // Dismiss the intro view too so user lands back on Settings.
                dismiss()
            }
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

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("How it works")
            phaseRow(symbol: "figure.cooldown", title: "Warmup", duration: "15 min", detail: "Easy spinning, gradually building.")
            phaseRow(symbol: "bolt.fill", title: "FTP Test", duration: "20 min", detail: "Hard but sustainable. Pace by feel.")
            phaseRow(symbol: "wind", title: "Cooldown", duration: "10 min", detail: "Easy spin to recover.")
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
