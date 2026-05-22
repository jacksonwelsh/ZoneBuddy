import Foundation
import Combine
import FTMSKit

enum TrainerMode: Sendable, Equatable {
    case off
    case erg
    case manualResistance
    /// FTMS Indoor Bike Simulation (opcode 0x11). Trainer applies physical
    /// resistance matching a wind speed + grade + Crr/Cw model; rider's own
    /// power determines actual speed. Used by Route Ride mode.
    case simulation
}

enum TrainerError: Sendable, Equatable {
    case controlLost
    case opcodeNotSupported
    case operationFailed
    case timeout
    case other(String)
}

struct TrainerCapabilities: Sendable, Equatable {
    let powerTargetSettingSupported: Bool
    let resistanceTargetSettingSupported: Bool
    /// FTMS opcode 0x11 (Indoor Bike Simulation Parameters). Required for
    /// Route Ride mode — without it the trainer can't apply grade resistance.
    let simulationParamsSupported: Bool
    let supportedPowerRange: ClosedRange<Int>?
    let supportedResistanceRange: ClosedRange<Double>?

    init(features: MachineFeatures) {
        self.powerTargetSettingSupported = features.powerTargetSettingSupported
        self.resistanceTargetSettingSupported = features.resistanceTargetSettingSupported
        self.simulationParamsSupported = features.indoorBikeSimulationParamsSupported
        self.supportedPowerRange = features.supportedPowerRange
        self.supportedResistanceRange = features.supportedResistanceRange
    }

    init(
        powerTargetSettingSupported: Bool,
        resistanceTargetSettingSupported: Bool,
        simulationParamsSupported: Bool = false,
        supportedPowerRange: ClosedRange<Int>?,
        supportedResistanceRange: ClosedRange<Double>?
    ) {
        self.powerTargetSettingSupported = powerTargetSettingSupported
        self.resistanceTargetSettingSupported = resistanceTargetSettingSupported
        self.simulationParamsSupported = simulationParamsSupported
        self.supportedPowerRange = supportedPowerRange
        self.supportedResistanceRange = supportedResistanceRange
    }
}

/// Subset of `FTMSBike` that `LiveTrainerController` actually depends on.
/// Lets tests inject a `MockFTMSBike` without bringing up CoreBluetooth.
/// Capabilities are surfaced via `TrainerCapabilities` (not `MachineFeatures`)
/// so test doubles don't need to fabricate the internal-init flag word.
@MainActor
protocol FTMSBikeControlling: AnyObject {
    var currentCapabilities: TrainerCapabilities? { get }
    var capabilitiesPublisher: AnyPublisher<TrainerCapabilities?, Never> { get }
    var machineStatusPublisher: AnyPublisher<MachineStatus, Never> { get }

    func enterErgMode(targetWatts: Int) async throws
    func setTargetPower(_ watts: Int) async throws
    func setTargetResistanceLevel(_ level: Double) async throws
    /// Bundled by `enterErgMode` internally; surfaced here so simulation
    /// mode can perform the same request-control + start handshake before
    /// sending the first set of simulation parameters.
    func requestControl() async throws
    func start() async throws
    func setSimulationParameters(
        windSpeedMS: Double,
        gradePercent: Double,
        rollingResistanceCoeff: Double,
        windResistanceCoeff: Double
    ) async throws
    func stopOrPause(pause: Bool) async throws
    func reset() async throws
}

extension FTMSBike: FTMSBikeControlling {
    var currentCapabilities: TrainerCapabilities? {
        features.map(TrainerCapabilities.init(features:))
    }

    var capabilitiesPublisher: AnyPublisher<TrainerCapabilities?, Never> {
        $features
            .map { $0.map(TrainerCapabilities.init(features:)) }
            .eraseToAnyPublisher()
    }
}

@MainActor
protocol TrainerControlling: AnyObject, Observable {
    var mode: TrainerMode { get }
    var capabilities: TrainerCapabilities? { get }
    var currentTargetWatts: Int? { get }
    var currentResistanceLevel: Double? { get }
    var currentGradePercent: Double? { get }
    var lastError: TrainerError? { get }
    /// True once the user has manually adjusted target watts since the last
    /// explicit `enableERG(...)` call. Workouts use this to stop auto-setting
    /// targets at interval boundaries.
    var ergUserOverridden: Bool { get }

    func enableERG(targetWatts: Int) async
    func disableERG() async
    func setTargetWatts(_ watts: Int) async
    func adjustTargetWatts(by delta: Int) async
    func setResistanceLevel(_ level: Double) async
    func enterSimulation(initialGrade: Double) async
    func setGrade(_ percent: Double) async
    func pause() async
    func resume() async
    func reset() async
}

@Observable
@MainActor
final class LiveTrainerController: TrainerControlling {
    private(set) var mode: TrainerMode = .off
    private(set) var capabilities: TrainerCapabilities?
    private(set) var currentTargetWatts: Int?
    private(set) var currentResistanceLevel: Double?
    private(set) var currentGradePercent: Double?
    private(set) var lastError: TrainerError?
    private(set) var ergUserOverridden: Bool = false

    @ObservationIgnored private weak var bike: (any FTMSBikeControlling)?
    @ObservationIgnored private var statusCancellable: AnyCancellable?
    @ObservationIgnored private var featuresCancellable: AnyCancellable?
    @ObservationIgnored private var lastSimWriteDate: Date?
    @ObservationIgnored private let dateProvider: @MainActor () -> Date

    /// Hard cap on grade values sent to the trainer. Mirrors `GPXParser.maxGradePercent`.
    static let maxGradePercent: Double = 20.0
    /// Throttle window — at most one sim-param write per second unless the delta is large.
    static let simWriteInterval: TimeInterval = 1.0
    /// If the new grade differs by at least this much from the last sent grade,
    /// the write goes through immediately even if we're inside the throttle window.
    static let simWriteImmediateDelta: Double = 1.0
    /// Sub-this-percent deltas inside the throttle window are dropped, even if
    /// the time-since-last write has crossed the boundary — keeps the BLE
    /// control point quiet when the rider is on a long flat.
    static let simWriteMinDelta: Double = 0.2

    init(bike: any FTMSBikeControlling, dateProvider: @escaping @MainActor () -> Date = { Date() }) {
        self.bike = bike
        self.dateProvider = dateProvider
        self.capabilities = bike.currentCapabilities
        featuresCancellable = bike.capabilitiesPublisher.sink { [weak self] caps in
            guard let self, let caps else { return }
            Task { @MainActor in
                self.capabilities = caps
            }
        }
        statusCancellable = bike.machineStatusPublisher.sink { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                self.handle(status: status)
            }
        }
    }

    func enableERG(targetWatts: Int) async {
        guard let bike else { return }
        let clamped = clampPower(targetWatts)
        do {
            try await bike.enterErgMode(targetWatts: clamped)
            mode = .erg
            currentTargetWatts = clamped
            ergUserOverridden = false
            lastError = nil
        } catch {
            lastError = map(error: error)
        }
    }

    func disableERG() async {
        guard let bike else {
            mode = .off
            return
        }
        do {
            try await bike.stopOrPause(pause: false)
        } catch {
            lastError = map(error: error)
        }
        mode = .off
        currentTargetWatts = nil
        ergUserOverridden = false
    }

    func setTargetWatts(_ watts: Int) async {
        guard let bike, mode == .erg else {
            await enableERG(targetWatts: watts)
            return
        }
        let clamped = clampPower(watts)
        do {
            try await bike.setTargetPower(clamped)
            currentTargetWatts = clamped
            lastError = nil
        } catch {
            lastError = map(error: error)
        }
    }

    func adjustTargetWatts(by delta: Int) async {
        let base = currentTargetWatts ?? 0
        let next = base + delta
        if mode != .erg {
            await enableERG(targetWatts: next)
        } else {
            await setTargetWatts(next)
        }
        // Any user nudge counts as a sticky manual override — the workout
        // engine stops auto-setting until ERG is explicitly re-enabled.
        ergUserOverridden = true
    }

    func enterSimulation(initialGrade: Double) async {
        guard let bike else { return }
        let clamped = clampGrade(initialGrade)

        // Trainers that were previously driven in ERG mode (Wahoo Kickr, Tacx)
        // keep holding the last power target until the controller is reset
        // or stopped, even after a new sim-params command arrives. Without
        // this stop, the rider feels their old ~1 W ERG hold while we think
        // we're in simulation mode — exactly the "no resistance in highest
        // gear" symptom. Mirror what `enterErgMode` does internally:
        // request control + start, then issue the mode-specific command.
        if mode == .erg || mode == .manualResistance {
            try? await bike.stopOrPause(pause: false)
        }
        try? await bike.requestControl()
        try? await bike.start()

        do {
            try await bike.setSimulationParameters(
                windSpeedMS: 0,
                gradePercent: clamped,
                rollingResistanceCoeff: GPXParser.defaultCrr,
                windResistanceCoeff: GPXParser.defaultCw
            )
            mode = .simulation
            currentTargetWatts = nil
            currentResistanceLevel = nil
            currentGradePercent = clamped
            lastSimWriteDate = dateProvider()
            ergUserOverridden = false
            lastError = nil
        } catch {
            // Most failure mode of interest is `.opcodeNotSupported`: the trainer
            // is a smart bike that doesn't speak sim mode. Surface the error so
            // the player UI can fall back to "trainer un-driven" + a toast.
            lastError = map(error: error)
        }
    }

    func setGrade(_ percent: Double) async {
        guard let bike, mode == .simulation else { return }
        let clamped = clampGrade(percent)
        let now = dateProvider()
        // If `lastSimWriteDate` is nil we just entered sim mode or were
        // resumed — force the write through so the trainer is re-anchored.
        if let lastGrade = currentGradePercent, let lastWrite = lastSimWriteDate {
            let delta = abs(clamped - lastGrade)
            let elapsed = now.timeIntervalSince(lastWrite)
            // Inside the throttle window — only push through if the grade has
            // moved enough to matter; small jitter is suppressed.
            if elapsed < Self.simWriteInterval && delta < Self.simWriteImmediateDelta {
                return
            }
            // Outside the throttle window but the rider is on a long flat —
            // skip if the delta is microscopic.
            if delta < Self.simWriteMinDelta {
                currentGradePercent = clamped
                return
            }
        }
        do {
            try await bike.setSimulationParameters(
                windSpeedMS: 0,
                gradePercent: clamped,
                rollingResistanceCoeff: GPXParser.defaultCrr,
                windResistanceCoeff: GPXParser.defaultCw
            )
            currentGradePercent = clamped
            lastSimWriteDate = now
            lastError = nil
        } catch {
            lastError = map(error: error)
        }
    }

    func setResistanceLevel(_ level: Double) async {
        guard let bike else { return }
        let clamped = clampResistance(level)
        do {
            try await bike.setTargetResistanceLevel(clamped)
            mode = .manualResistance
            currentResistanceLevel = clamped
            currentTargetWatts = nil
            lastError = nil
        } catch {
            lastError = map(error: error)
        }
    }

    func pause() async {
        guard let bike else { return }
        do {
            try await bike.stopOrPause(pause: true)
        } catch {
            lastError = map(error: error)
        }
    }

    func resume() async {
        // Re-issue the last control target so the trainer ramps back to where
        // it was — ERG target for ERG mode, last grade for simulation.
        if mode == .erg, let target = currentTargetWatts {
            await setTargetWatts(target)
        } else if mode == .simulation, let grade = currentGradePercent {
            // Force the next setGrade through by clearing the throttle window.
            lastSimWriteDate = nil
            await setGrade(grade)
        }
    }

    func reset() async {
        guard let bike else {
            mode = .off
            currentTargetWatts = nil
            currentResistanceLevel = nil
            currentGradePercent = nil
            lastSimWriteDate = nil
            ergUserOverridden = false
            return
        }
        // Always release the trainer before resetting. Some trainers (notably
        // Wahoo Kickr in sim mode) keep applying the last grade/power after a
        // Reset alone — the explicit Stop ensures the flywheel goes free and
        // the rider can spin out the cooldown without fighting residual load.
        try? await bike.stopOrPause(pause: false)
        do {
            try await bike.reset()
        } catch {
            lastError = map(error: error)
        }
        mode = .off
        currentTargetWatts = nil
        currentResistanceLevel = nil
        currentGradePercent = nil
        lastSimWriteDate = nil
        ergUserOverridden = false
    }

    private func handle(status: MachineStatus) {
        switch status {
        case .controlPermissionLost:
            mode = .off
            currentTargetWatts = nil
            lastError = .controlLost
        case .targetPowerChanged(let watts):
            currentTargetWatts = watts
        case .targetResistanceLevelChanged(let level):
            currentResistanceLevel = level
        default:
            break
        }
    }

    private func clampPower(_ watts: Int) -> Int {
        guard let range = capabilities?.supportedPowerRange else { return max(0, watts) }
        return min(max(watts, range.lowerBound), range.upperBound)
    }

    private func clampResistance(_ level: Double) -> Double {
        guard let range = capabilities?.supportedResistanceRange else { return max(0, level) }
        return min(max(level, range.lowerBound), range.upperBound)
    }

    private func clampGrade(_ percent: Double) -> Double {
        min(max(percent, -Self.maxGradePercent), Self.maxGradePercent)
    }

    private func map(error: Error) -> TrainerError {
        if let ftms = error as? FTMSError {
            switch ftms {
            case .controlPointError(.opcodeNotSupported): return .opcodeNotSupported
            case .controlPointError(.operationFailed): return .operationFailed
            case .controlPointError(.controlNotPermitted): return .controlLost
            case .controlPointTimeout: return .timeout
            default: return .other(String(describing: ftms))
            }
        }
        return .other(String(describing: error))
    }
}
