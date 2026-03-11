import SwiftUI
import FTMSKit

struct BikeConnectionView: View {
    var bikeManager: BikeConnecting = LiveBikeConnectionManager.shared

    var body: some View {
        List {
            if bikeManager.isConnected {
                connectedSection
            } else {
                scanningSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bike")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear {
            bikeManager.stopScanning()
        }
    }

    private var connectedSection: some View {
        Section {
            HStack {
                Label(bikeManager.connectedBikeName ?? "Bike", systemImage: "bicycle")
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if let data = bikeManager.latestBikeData {
                LabeledContent("Power", value: "\(data.instantaneousPower ?? 0) W")
                LabeledContent("Cadence", value: "\(Int(data.instantaneousCadence ?? 0)) rpm")
                if let hr = data.heartRate {
                    LabeledContent("Heart Rate", value: "\(hr) bpm")
                }
            }

            Button("Disconnect", role: .destructive) {
                bikeManager.disconnect()
            }
        } header: {
            Text("Connected")
        }
    }

    private var scanningSection: some View {
        Group {
            Section {
                if bikeManager.isScanning {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Scanning for FTMS bikes...")
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
                                signalStrengthIcon(rssi: device.rssi)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func signalStrengthIcon(rssi: Int) -> some View {
        let level: Int
        switch rssi {
        case -50...0: level = 3
        case -70 ..< -50: level = 2
        case -90 ..< -70: level = 1
        default: level = 0
        }
        let name = level == 0 ? "wifi.slash" : "wifi"
        return Image(systemName: name)
            .symbolVariant(level >= 3 ? .none : .slash)
            .font(.caption)
    }
}
