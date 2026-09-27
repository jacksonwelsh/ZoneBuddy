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

    /// Locally-tracked "intended" target. Set immediately on release so the
    /// readout reacts without waiting for the BLE round trip, then cleared
    /// after the debounced send completes and the controller has caught up.
    @State private var pendingTargetWatts: Int?
    @State private var ergDebounceTask: Task<Void, Never>?
    @State private var pendingLevel: Double?
    @State private var levelDebounceTask: Task<Void, Never>?

    /// How long to wait after the last adjustment before pushing the accumulated
    /// adjustment to the trainer. Coalesces quick repeated changes while
    /// keeping individual adjustments responsive.
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
        case .simulation:
            // Route Ride owns the trainer in this mode; the picker is hidden
            // by the player UI when this view is presented. Return a sensible
            // fallback so the binding has a well-defined value.
            return .erg
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
                powerDial
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
                Text("Swipe the dial to set watts in 5 W steps. ZoneBuddy stops auto-setting at interval boundaries after a manual adjustment.")
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
            powerDial
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

    private var powerDial: some View {
        TrainerPowerDial(
            watts: pendingTargetWatts ?? controller?.currentTargetWatts
                ?? capabilities?.supportedPowerRange?.lowerBound ?? 0,
            range: capabilities?.supportedPowerRange ?? 0...Int(Int16.max),
            onCommit: { target in
                let current = pendingTargetWatts ?? controller?.currentTargetWatts ?? 0
                bumpERG(by: target - current)
            }
        )
        .disabled(controller == nil || capabilities?.powerTargetSettingSupported != true)
    }

    /// Accumulate ERG changes locally and flush after adjustments settle. Sending a
    /// single net delta avoids the BLE-serialization race where rapid adjustments
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
            // Only clear if the user hasn't adjusted again while the BLE write
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
    /// current zone target (via `reEnableERGForCurrentInterval` — falls back
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

/// A horizontal thumbwheel: drag the scale beneath the fixed selection mark.
/// Gesture state resets on cancellation without sending a trainer command.
private struct TrainerPowerDial: View {
    let watts: Int
    let range: ClosedRange<Int>
    var onCommit: (Int) -> Void

    @GestureState private var drag: DialDrag?
    // GestureState can reset before onEnded. Keep the accepted drag's starting
    // target separately so release does not discard the user's selection.
    @State private var dragStartForCommit: Int?

    private struct DialDrag {
        let start: Int
        var translation: CGFloat
    }

    private let tickSpacing: CGFloat = 12

    private func target(start: Int, translation: CGFloat) -> Int {
        TrainerPowerSteps.target(
            start: start,
            steps: Int((-translation / tickSpacing).rounded()),
            range: range
        )
    }

    private var displayedWatts: Int {
        guard let drag else { return watts }
        return target(start: drag.start, translation: drag.translation)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(displayedWatts)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                Text("W")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geometry in
                let center = geometry.size.width / 2
                let radius = Int(ceil(center / tickSpacing)) + 1
                let nearestTick = displayedWatts / 5
                ZStack(alignment: .top) {
                    ForEach((-radius)...radius, id: \.self) { offset in
                        let tick = (nearestTick + offset) * 5
                        if range.contains(tick) {
                            let major = tick.isMultiple(of: 25)
                            VStack(spacing: 8) {
                                Capsule()
                                    .fill(.secondary.opacity(major ? 0.75 : 0.35))
                                    .frame(width: 2, height: major ? 25 : 14)
                                    .frame(height: 25, alignment: .top)
                                if major {
                                    Text("\(tick)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .position(
                                x: center + CGFloat(tick - displayedWatts) / 5 * tickSpacing,
                                y: 29
                            )
                        }
                    }
                    Capsule()
                        .fill(.tint)
                        .frame(width: 3, height: 31)
                }
                .frame(width: geometry.size.width, height: 64)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0),
                                .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.88),
                                .init(color: .clear, location: 1)],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
            }
            .frame(height: 64)

            Text("Swipe to adjust")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($drag) { value, state, _ in
                    guard state != nil || abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    state = DialDrag(start: state?.start ?? watts, translation: value.translation.width)
                }
                .onChanged { value in
                    // Refresh on every event, including a new gesture after a
                    // cancellation, so an old starting target cannot leak in.
                    if let drag {
                        dragStartForCommit = drag.start
                    } else if abs(value.translation.width) > abs(value.translation.height) {
                        dragStartForCommit = watts
                    } else {
                        dragStartForCommit = nil
                    }
                }
                .onEnded { value in
                    defer { dragStartForCommit = nil }
                    guard let start = dragStartForCommit else { return }
                    let next = target(start: start, translation: value.translation.width)
                    if next != watts { onCommit(next) }
                }
        )
        .sensoryFeedback(.selection, trigger: displayedWatts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target power")
        .accessibilityValue("\(displayedWatts) watts")
        .accessibilityHint("Swipe up or down to select the next 5 watt step")
        .accessibilityAdjustableAction { direction in
            let delta: Int
            switch direction {
            case .increment: delta = 5
            case .decrement: delta = -5
            @unknown default: return
            }
            let next = TrainerPowerSteps.target(start: watts, steps: delta > 0 ? 1 : -1, range: range)
            if next != watts { onCommit(next) }
        }
    }
}

#Preview("Power Dial — Interactive iPad") {
    @Previewable @State var watts = 183

    NavigationStack {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("ERG", systemImage: "scope")
                        .font(.headline)
                    TrainerPowerDial(watts: watts, range: 50...1000) { watts = $0 }

                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Text("Applied target: \(watts) W")
                    .font(.headline.monospacedDigit())
                Text("Drag the dial, then release to apply. This preview uses local state and does not connect to a trainer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Minimum") { watts = 50 }
                    Button("183 W") { watts = 183 }
                    Button("Maximum") { watts = 1000 }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Trainer Dial Preview")
    }
}
