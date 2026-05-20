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

    /// Locally-tracked "intended" target. Set immediately on each tap so the
    /// readout reacts without waiting for the BLE round trip, then cleared
    /// after the debounced send completes and the controller has caught up.
    @State private var pendingTargetWatts: Int?
    @State private var ergDebounceTask: Task<Void, Never>?
    @State private var pendingLevel: Double?
    @State private var levelDebounceTask: Task<Void, Never>?

    /// How long to wait after the last tap before pushing the accumulated
    /// adjustment to the trainer. Long enough to coalesce a flurry of taps,
    /// short enough that a single tap still feels responsive.
    private static let trainerWriteDebounce: Duration = .milliseconds(220)

    private var controller: (any TrainerControlling)? {
        viewModel.trainerController
    }

    private var capabilities: TrainerCapabilities? {
        controller?.capabilities
    }

    /// Whether the picker showing ERG/Level is meaningful — true only when the
    /// trainer supports both control schemes. With only one supported, we hide
    /// the picker and show that mode's controls unconditionally.
    private var supportsBothModes: Bool {
        capabilities?.powerTargetSettingSupported == true
            && capabilities?.resistanceTargetSettingSupported == true
    }

    /// What the segmented picker reflects — derived from the controller's
    /// current `TrainerMode`. `.off` defaults to ERG when supported, then Level.
    private var selectedMode: ControlMode {
        switch controller?.mode {
        case .manualResistance: return .level
        case .erg: return .erg
        case .off, .none:
            return capabilities?.powerTargetSettingSupported == true ? .erg : .level
        }
    }

    private enum ControlMode: Hashable { case erg, level }

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
            if supportsBothModes {
                modePickerSection
            }
            if selectedMode == .erg {
                ergSection
            } else {
                levelSection
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
            if supportsBothModes {
                inlineModePicker
            }
            if selectedMode == .erg {
                inlineERGControls
            } else {
                inlineLevelControls
            }
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
    private var modePickerSection: some View {
        Section {
            Picker("Mode", selection: modeBinding) {
                Text("ERG").tag(ControlMode.erg)
                Text("Level").tag(ControlMode.level)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(selectedMode == .erg
                 ? "ERG holds a power target — the trainer adjusts resistance so you hit the watts."
                 : "Level holds a fixed resistance — your power follows your effort.")
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
    private var levelSection: some View {
        if capabilities?.resistanceTargetSettingSupported == true {
            Section {
                levelReadout
                levelStepperRow
            } header: {
                Text("Level")
            } footer: {
                Text("Tap ± to change resistance. Auto-ERG won't engage at interval boundaries while you're in Level.")
            }
        }
    }

    // MARK: - Inline sections

    @ViewBuilder
    private var inlineHeader: some View {
        HStack {
            Image(systemName: selectedMode == .erg ? "scope" : "dial.medium")
            Text(selectedMode == .erg ? "ERG" : "Level").font(.headline)
            Spacer()
            if selectedMode == .erg, controller?.ergUserOverridden == true {
                Button("Re-enable") {
                    viewModel.reEnableERGForCurrentInterval()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var inlineModePicker: some View {
        Picker("Mode", selection: modeBinding) {
            Text("ERG").tag(ControlMode.erg)
            Text("Level").tag(ControlMode.level)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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

    @ViewBuilder
    private var inlineLevelControls: some View {
        if capabilities?.resistanceTargetSettingSupported == true {
            HStack(spacing: 16) {
                levelStepperButton(delta: -1)
                Spacer()
                VStack(spacing: 2) {
                    Text(levelLabel)
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                levelStepperButton(delta: 1)
            }
        } else {
            Text("Trainer doesn't support resistance levels")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Components

    private var wattsLabel: String {
        if let pending = pendingTargetWatts { return "\(pending)" }
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
            bumpERG(by: delta)
        } label: {
            Text(delta > 0 ? "+\(delta) W" : "\(delta) W")
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(controller == nil || capabilities?.powerTargetSettingSupported != true)
    }

    /// Accumulate ERG nudges locally and flush after taps settle. Sending a
    /// single net delta avoids the BLE-serialization race where rapid taps
    /// each captured the same stale `currentTargetWatts` as their base.
    private func bumpERG(by delta: Int) {
        let base = pendingTargetWatts ?? controller?.currentTargetWatts ?? 0
        let next = clampPower(base + delta)
        pendingTargetWatts = next
        ergDebounceTask?.cancel()
        ergDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: Self.trainerWriteDebounce)
            guard !Task.isCancelled, let target = pendingTargetWatts else { return }
            let current = controller?.currentTargetWatts ?? 0
            await controller?.adjustTargetWatts(by: target - current)
            // Only clear if the user hasn't tapped again while the BLE write
            // was in flight — otherwise a newer pending target would be lost.
            if pendingTargetWatts == target {
                pendingTargetWatts = nil
            }
        }
    }

    private func clampPower(_ watts: Int) -> Int {
        guard let range = capabilities?.supportedPowerRange else { return max(0, watts) }
        return min(max(watts, range.lowerBound), range.upperBound)
    }

    // MARK: - Level components

    /// Current resistance level — defaults to the bottom of the supported range
    /// before the user has set anything, so the readout doesn't blink "—" the
    /// first time they tap into Level mode.
    private var currentLevel: Double {
        if let pending = pendingLevel { return pending }
        if let level = controller?.currentResistanceLevel { return level }
        return capabilities?.supportedResistanceRange?.lowerBound ?? 0
    }

    private var levelLabel: String {
        if pendingLevel != nil { return "\(Int(currentLevel.rounded()))" }
        guard controller?.currentResistanceLevel != nil
                || capabilities?.supportedResistanceRange != nil else { return "—" }
        return "\(Int(currentLevel.rounded()))"
    }

    @ViewBuilder
    private var levelReadout: some View {
        HStack {
            Text("Resistance")
                .foregroundStyle(.secondary)
            Spacer()
            Text(levelLabel)
                .font(.title2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var levelStepperRow: some View {
        HStack(spacing: 16) {
            levelStepperButton(delta: -1)
            Spacer()
            levelStepperButton(delta: 1)
        }
        .padding(.vertical, 4)
    }

    private func levelStepperButton(delta: Int) -> some View {
        Button {
            bumpLevel(by: Double(delta))
        } label: {
            Text(delta > 0 ? "+\(delta)" : "\(delta)")
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(controller == nil || capabilities?.resistanceTargetSettingSupported != true)
    }

    /// Mirrors `bumpERG` for resistance level — accumulate locally, then
    /// flush a single `setResistanceLevel` after the debounce window.
    private func bumpLevel(by delta: Double) {
        let base = pendingLevel
            ?? controller?.currentResistanceLevel
            ?? capabilities?.supportedResistanceRange?.lowerBound
            ?? 0
        let next = clampResistance(base + delta)
        pendingLevel = next
        levelDebounceTask?.cancel()
        levelDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: Self.trainerWriteDebounce)
            guard !Task.isCancelled, let target = pendingLevel else { return }
            await controller?.setResistanceLevel(target)
            if pendingLevel == target {
                pendingLevel = nil
            }
        }
    }

    private func clampResistance(_ level: Double) -> Double {
        guard let range = capabilities?.supportedResistanceRange else { return max(0, level) }
        return min(max(level, range.lowerBound), range.upperBound)
    }

    // MARK: - Mode picker

    /// Binding for the segmented mode picker. The getter is derived state
    /// (`selectedMode`); the setter switches the trainer over: ERG snaps to the
    /// current zone midpoint (via `reEnableERGForCurrentInterval` — falls back
    /// to the last target or capability lower bound when no interval is
    /// active), Level engages `setResistanceLevel` at the current/last level.
    private var modeBinding: Binding<ControlMode> {
        Binding(
            get: { selectedMode },
            set: { newMode in
                guard let controller else { return }
                switch newMode {
                case .erg:
                    if viewModel.ergTargetWattsForCurrentInterval != nil {
                        viewModel.reEnableERGForCurrentInterval()
                    } else {
                        // No prescribed target (e.g. Free Ride / warmup) — pick
                        // up the last target if we had one, otherwise the
                        // bottom of the trainer's supported power range.
                        let fallback = controller.currentTargetWatts
                            ?? capabilities?.supportedPowerRange?.lowerBound
                            ?? 100
                        Task { await controller.enableERG(targetWatts: fallback) }
                    }
                case .level:
                    let startLevel = controller.currentResistanceLevel
                        ?? capabilities?.supportedResistanceRange?.lowerBound
                        ?? 0
                    Task { await controller.setResistanceLevel(startLevel) }
                }
            }
        )
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
