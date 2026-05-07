import SwiftUI

/// Post-test result screen shown when an FTP test workout finishes.
/// Displays the computed FTP (avg × 0.95) and lets the user save it as their FTP
/// or discard the result. If no power data was captured, shows an error state.
struct FTPTestResultView: View {
    let avgPower: Int?
    let computedFTP: Int?
    let onDone: () -> Void

    @State private var settings = SettingsManager.shared
    @State private var didSave = false

    private var previousFTP: Int { settings.functionalThresholdPower }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerIcon
                    if let computedFTP {
                        resultBlock(computedFTP: computedFTP)
                    } else {
                        noDataBlock
                    }
                    Spacer(minLength: 16)
                    actionButtons
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("FTP Test Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headerIcon: some View {
        Image(systemName: didSave ? "checkmark.seal.fill" : "stopwatch")
            .font(.system(size: 64))
            .foregroundStyle(.tint)
            .padding(.top, 12)
    }

    @ViewBuilder
    private func resultBlock(computedFTP: Int) -> some View {
        VStack(spacing: 6) {
            Text(didSave ? "FTP Saved" : "Calculated FTP")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(computedFTP)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("W")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            if let avgPower {
                Text("Average over 20 min: \(avgPower) W × 0.95")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !didSave && previousFTP != computedFTP {
                Text("Previous FTP: \(previousFTP) W")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var noDataBlock: some View {
        VStack(spacing: 8) {
            Text("No Power Data Captured")
                .font(.title3.weight(.semibold))
            Text("We didn't receive power readings from the bike during the test, so an FTP couldn't be calculated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let computedFTP, !didSave {
            VStack(spacing: 12) {
                Button {
                    settings.functionalThresholdPower = computedFTP
                    withAnimation { didSave = true }
                } label: {
                    Text("Save as my FTP")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Discard", role: .destructive, action: onDone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Button {
                onDone()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview("Has Result") {
    FTPTestResultView(avgPower: 258, computedFTP: 245, onDone: {})
}

#Preview("No Data") {
    FTPTestResultView(avgPower: nil, computedFTP: nil, onDone: {})
}
