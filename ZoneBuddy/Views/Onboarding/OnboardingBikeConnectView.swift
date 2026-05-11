import SwiftUI
import FTMSKit

struct OnboardingBikeConnectView: View {
    var bikeManager: any BikeConnecting = BikeManagerProvider.current
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScaffold(
            icon: "bicycle.circle",
            title: "Connect your bike",
            subtitle: bikeManager.isConnected ? "Connected and ready." : "Make sure your bike is on and broadcasting."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if bikeManager.isConnected {
                    connectedSection
                } else {
                    scanningSection
                    if !bikeManager.discoveredDevices.isEmpty {
                        availableSection
                    }
                }
            }
        } bottomBar: {
            VStack(spacing: 4) {
                OnboardingPrimaryButton(title: bikeManager.isConnected ? "Continue" : "Skip for Now", action: {
                    bikeManager.stopScanning()
                    onContinue()
                })
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

    private var connectedSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(bikeManager.connectedBikeName ?? "Bike")
                    .font(.body.weight(.semibold))
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var scanningSection: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(bikeManager.isScanning ? "Scanning for FTMS bikes…" : "Tap a bike below to connect.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
            ForEach(bikeManager.discoveredDevices) { device in
                Button {
                    bikeManager.connect(to: device)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bicycle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        Text(device.name ?? "Unknown Bike")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        }
    }
}
