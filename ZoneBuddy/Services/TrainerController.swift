import Foundation
import Combine
import FTMSKit

enum TrainerMode: Sendable, Equatable {
    case off
    case erg
    case manualResistance
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
    let supportedPowerRange: ClosedRange<Int>?
    let supportedResistanceRange: ClosedRange<Double>?

    init(features: MachineFeatures) {
        self.powerTargetSettingSupported = features.powerTargetSettingSupported
        self.resistanceTargetSettingSupported = features.resistanceTargetSettingSupported
        self.supportedPowerRange = features.supportedPowerRange
        self.supportedResistanceRange = features.supportedResistanceRange
    }

    init(
        powerTargetSettingSupported: Bool,
        resistanceTargetSettingSupported: Bool,
        supportedPowerRange: ClosedRange<Int>?,
        supportedResistanceRange: ClosedRange<Double>?
    ) {
        self.powerTargetSettingSupported = powerTargetSettingSupported
        self.resistanceTargetSettingSupported = resistanceTargetSettingSupported
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
    private(set) var lastError: TrainerError?
    private(set) var ergUserOverridden: Bool = false

    @ObservationIgnored private weak var bike: (any FTMSBikeControlling)?
    @ObservationIgnored private var statusCancellable: AnyCancellable?
    @ObservationIgnored private var featuresCancellable: AnyCancellable?

    init(bike: any FTMSBikeControlling) {
        self.bike = bike
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
        // Re-issue the last ERG target so the trainer ramps back to where it was.
        if mode == .erg, let target = currentTargetWatts {
            await setTargetWatts(target)
        }
    }

    func reset() async {
        guard let bike else {
            mode = .off
            currentTargetWatts = nil
            currentResistanceLevel = nil
            ergUserOverridden = false
            return
        }
        do {
            try await bike.reset()
        } catch {
            lastError = map(error: error)
        }
        mode = .off
        currentTargetWatts = nil
        currentResistanceLevel = nil
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
