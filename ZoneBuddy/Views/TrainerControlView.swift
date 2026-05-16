import SwiftUI
import FTMSKit

/// Trainer control surface. Rendered as a sheet on iPhone (compact width) and
/// inline within the iPad player layout. All state lives on the bike manager's
/// `TrainerControlling` — this view just observes and dispatches.
struct TrainerControlView: View {
    var viewModel: WorkoutPlayerViewModel
    var presentation: Presentation = .sheet
    var onDismiss: (() -> Void)? = nil

    enum Presentation {
        case sheet      // iPhone — modal with its own background
        case inline     // iPad — transparent, sits inside the player layout
    }

    private var controller: (any TrainerControlling)? {
        viewModel.trainerController
    }

    private var capabilities: TrainerCapabilities? {
        controller?.capabilities
    }

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                NavigationStack { sheetBody }
            case .inline:
                inlineBody
            }
        }
    }

    @ViewBuilder
    private var sheetBody: some View {
        Form {
            statusSection
            ergSection
            if capabilities?.resistanceTargetSettingSupported == true,
               controller?.mode != .erg {
                resistanceSection
            }
        }
        .navigationTitle("Trainer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDismiss?() }
            }
        }
    }

    @ViewBuilder
    private var inlineBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            inlineHeader
            inlineERGControls
            if let error = controller?.lastError, error == .controlLost {
                controlLostBanner
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Sheet sections

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: viewModel.isConnectedToBike ? "bicycle" : "bicycle.slash")
                    .foregroundStyle(viewModel.isConnectedToBike ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(viewModel.bikeManager?.connectedBikeName ?? "No trainer connected")
                        .font(.headline)
                    if let caps = capabilities {
                        Text(capabilitySummary(caps))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let error = controller?.lastError, error == .controlLost {
                controlLostBanner
            }
        }
    }

    @ViewBuilder
    private var ergSection: some View {
        if capabilities?.powerTargetSettingSupported == true {
            Section {
                wattsReadout
                stepperRow
                if controller?.ergUserOverridden == true {
                    Button {
                        viewModel.reEnableERGForCurrentInterval()
                    } label: {
                        Label("Re-enable ERG", systemImage: "scope")
                    }
                }
            } header: {
                Text("ERG Mode")
            } footer: {
                Text("Tap ± to nudge the target. ZoneBuddy stops auto-setting at interval boundaries after a manual adjustment.")
            }
        }
    }

    @ViewBuilder
    private var resistanceSection: some View {
        if let range = capabilities?.supportedResistanceRange {
            Section("Resistance") {
                let level = controller?.currentResistanceLevel ?? range.lowerBound
                HStack {
                    Text("\(Int(level))")
                        .font(.title2.monospacedDigit())
                    Slider(
                        value: Binding(
                            get: { controller?.currentResistanceLevel ?? range.lowerBound },
                            set: { newValue in
                                Task { await controller?.setResistanceLevel(newValue) }
                            }
                        ),
                        in: range
                    )
                }
            }
        }
    }

    // MARK: - Inline sections

    @ViewBuilder
    private var inlineHeader: some View {
        HStack {
            Image(systemName: "scope")
            Text("ERG").font(.headline)
            Spacer()
            if controller?.ergUserOverridden == true {
                Button("Re-enable") {
                    viewModel.reEnableERGForCurrentInterval()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var inlineERGControls: some View {
        if capabilities?.powerTargetSettingSupported == true {
            HStack(spacing: 16) {
                stepperButton(delta: -5)
                Spacer()
                VStack(spacing: 2) {
                    Text(wattsLabel)
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("watts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stepperButton(delta: 5)
            }
        } else {
            Text("Trainer doesn't support power targets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Components

    private var wattsLabel: String {
        guard let watts = controller?.currentTargetWatts else { return "—" }
        return "\(watts)"
    }

    @ViewBuilder
    private var wattsReadout: some View {
        HStack {
            Text("Target")
                .foregroundStyle(.secondary)
            Spacer()
            Text(wattsLabel + " W")
                .font(.title2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var stepperRow: some View {
        HStack(spacing: 16) {
            stepperButton(delta: -5)
            Spacer()
            stepperButton(delta: 5)
        }
        .padding(.vertical, 4)
    }

    private func stepperButton(delta: Int) -> some View {
        Button {
            Task { await controller?.adjustTargetWatts(by: delta) }
        } label: {
            Text(delta > 0 ? "+\(delta) W" : "\(delta) W")
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(controller == nil || capabilities?.powerTargetSettingSupported != true)
    }

    @ViewBuilder
    private var controlLostBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Another app took control").font(.subheadline.weight(.semibold))
                Text("Retake to apply ERG targets").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retake") {
                viewModel.reEnableERGForCurrentInterval()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func capabilitySummary(_ caps: TrainerCapabilities) -> String {
        var bits: [String] = []
        if caps.powerTargetSettingSupported { bits.append("ERG") }
        if caps.resistanceTargetSettingSupported { bits.append("Resistance") }
        if let range = caps.supportedPowerRange {
            bits.append("\(range.lowerBound)–\(range.upperBound) W")
        }
        return bits.joined(separator: " · ")
    }
}
