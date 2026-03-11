import SwiftUI
import FTMSKit

/// Sheet shown before starting a workout when the user has enabled "Prompt Before Workout"
/// and no bike is currently connected. Scans for bikes and allows quick connection.
struct BikePromptSheet: View {
    var bikeManager: BikeConnecting = LiveBikeConnectionManager.shared
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if bikeManager.isConnected {
                    Section {
                        HStack {
                            Label(bikeManager.connectedBikeName ?? "Bike", systemImage: "bicycle")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Connected")
                    }
                } else {
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
                                    }
                                }
                            }
                        }
                    }
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
                    .disabled(!bikeManager.isConnected)
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
        .presentationDetents([.medium])
    }
}
