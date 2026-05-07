import SwiftUI
import FTMSKit

/// Sheet shown before starting a workout when the user has enabled "Prompt Before Workout"
/// and either no bike is connected, or the connected bike has not yet reported a non-zero
/// pedaling metric. Allows the user to scan/select a bike, manually reconnect to recover from
/// the "stuck at zero" state, or skip the bike entirely.
struct BikePromptSheet: View {
    var bikeManager: BikeConnecting = LiveBikeConnectionManager.shared
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if bikeManager.isConnected {
                    connectedSection
                    bikeActionsSection
                } else {
                    scanningSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Connect Bike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        bikeManager.stopScanning()
                        onStart()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        bikeManager.stopScanning()
                        onStart()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isReadyToStart)
                }
            }
            .onAppear {
                if !bikeManager.isConnected && !bikeManager.isScanning {
                    bikeManager.startScanning()
                }
            }
            .onDisappear {
                bikeManager.stopScanning()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isReadyToStart: Bool {
        bikeManager.isConnected && bikeManager.hasReceivedNonZeroMetric
    }

    @ViewBuilder
    private var connectedSection: some View {
        Section {
            HStack {
                Label(bikeManager.connectedBikeName ?? "Bike", systemImage: "bicycle")
                Spacer()
                if bikeManager.isReconnecting {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Connected")
        }

        Section {
            statusRow
        } header: {
            Text(statusHeader)
        } footer: {
            Text(statusFooter)
        }
    }

    private var statusHeader: String {
        if bikeManager.isReconnecting { return "Reconnecting" }
        if bikeManager.hasReceivedNonZeroMetric { return "Ready" }
        return "Pedal to Start"
    }

    private var statusFooter: String {
        if bikeManager.isReconnecting {
            return "Re-establishing the connection so the bike starts reporting metrics."
        }
        if bikeManager.hasReceivedNonZeroMetric {
            return "Tap Start to begin your workout."
        }
        return "Give the pedals a turn to confirm the bike is reporting power. If nothing happens after a few seconds, try reconnecting or pick a different bike."
    }

    @ViewBuilder
    private var statusRow: some View {
        if bikeManager.isReconnecting {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Reconnecting…")
                    .foregroundStyle(.secondary)
            }
        } else if bikeManager.hasReceivedNonZeroMetric {
            Label {
                Text("Bike is reporting metrics")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let data = bikeManager.latestBikeData {
                liveMetricsRow(data: data)
            }
        } else {
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Waiting for the first non-zero metric…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func liveMetricsRow(data: BikeData) -> some View {
        HStack(spacing: 16) {
            metricChip(value: "\(data.instantaneousPower ?? 0)", unit: "W", label: "Power")
            metricChip(value: "\(Int(data.instantaneousCadence ?? 0))", unit: "rpm", label: "Cadence")
            if let speed = data.instantaneousSpeed, speed > 0 {
                metricChip(value: String(format: "%.1f", speed), unit: "km/h", label: "Speed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricChip(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bikeActionsSection: some View {
        Section {
            Button {
                bikeManager.attemptReconnect()
            } label: {
                Label("Reconnect Bike", systemImage: "arrow.clockwise")
            }
            .disabled(bikeManager.isReconnecting)

            Button(role: .destructive) {
                bikeManager.disconnect()
                bikeManager.startScanning()
            } label: {
                Label("Choose Different Bike", systemImage: "bicycle.circle")
            }
        } footer: {
            Text("Reconnecting often clears the stuck state where the bike reports zero power even while you're pedaling.")
        }
    }

    @ViewBuilder
    private var scanningSection: some View {
        Section {
            if bikeManager.isScanning {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Scanning for FTMS bikes…")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    bikeManager.startScanning()
                } label: {
                    Label("Scan for Bikes", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }

        if !bikeManager.discoveredDevices.isEmpty {
            Section("Available Bikes") {
                ForEach(bikeManager.discoveredDevices) { device in
                    Button {
                        bikeManager.connect(to: device)
                    } label: {
                        HStack {
                            Label(device.name ?? "Unknown Bike", systemImage: "bicycle")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}
