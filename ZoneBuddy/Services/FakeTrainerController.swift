#if DEBUG
import Foundation

/// Debug-only stand-in for `LiveTrainerController`. Mirrors public state so the
/// trainer UI and ViewModel hooks can be exercised without a real FTMS bike.
@Observable
@MainActor
final class FakeTrainerController: TrainerControlling {
    private(set) var mode: TrainerMode = .off
    var capabilities: TrainerCapabilities? = TrainerCapabilities(
        powerTargetSettingSupported: true,
        resistanceTargetSettingSupported: true,
        simulationParamsSupported: true,
        supportedPowerRange: 50...1000,
        supportedResistanceRange: 0.0...100.0
    )
    private(set) var currentTargetWatts: Int?
    private(set) var currentResistanceLevel: Double?
    private(set) var currentGradePercent: Double?
    var lastError: TrainerError?
    private(set) var ergUserOverridden: Bool = false

    func enableERG(targetWatts: Int) async {
        mode = .erg
        currentTargetWatts = targetWatts
        ergUserOverridden = false
        #if DEBUG
        SimulatorFakes.shared.targetPower = targetWatts
        #endif
    }

    func disableERG() async {
        mode = .off
        currentTargetWatts = nil
        ergUserOverridden = false
    }

    func setTargetWatts(_ watts: Int) async {
        mode = .erg
        currentTargetWatts = watts
        #if DEBUG
        SimulatorFakes.shared.targetPower = watts
        #endif
    }

    func adjustTargetWatts(by delta: Int) async {
        let base = currentTargetWatts ?? 0
        await setTargetWatts(base + delta)
        ergUserOverridden = true
    }

    func setResistanceLevel(_ level: Double) async {
        mode = .manualResistance
        currentResistanceLevel = level
        currentTargetWatts = nil
        #if DEBUG
        // Level mode means no power target — drop the simulated bike to an
        // easy-spin baseline so the rider visually sees the trainer released
        // instead of the previous ERG target lingering in the power readout.
        SimulatorFakes.shared.targetPower = 80
        #endif
    }

    func enterSimulation(initialGrade: Double) async {
        mode = .simulation
        currentTargetWatts = nil
        currentResistanceLevel = nil
        currentGradePercent = initialGrade
    }

    func setGrade(_ percent: Double) async {
        guard mode == .simulation else { return }
        currentGradePercent = percent
    }

    func pause() async {}
    func resume() async {
        if mode == .erg, let target = currentTargetWatts {
            await setTargetWatts(target)
        }
    }

    func reset() async {
        mode = .off
        currentTargetWatts = nil
        currentResistanceLevel = nil
        currentGradePercent = nil
        ergUserOverridden = false
    }
}
#endif
