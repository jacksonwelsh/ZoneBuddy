import Testing
import Foundation
import Combine
import FTMSKit
@testable import ZoneBuddy

@MainActor
struct TrainerControllerTests {
    private func defaultCapabilities() -> TrainerCapabilities {
        TrainerCapabilities(
            powerTargetSettingSupported: true,
            resistanceTargetSettingSupported: true,
            supportedPowerRange: 50...500,
            supportedResistanceRange: 0...100
        )
    }

    private func wait() async {
        // Drain MainActor work so publisher-driven state settles before assertions.
        try? await Task.sleep(for: .milliseconds(20))
    }

    @Test
    func enableERGRoutesThroughBike() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 200)

        #expect(bike.ergCalls == [200])
        #expect(controller.mode == .erg)
        #expect(controller.currentTargetWatts == 200)
        #expect(controller.ergUserOverridden == false)
    }

    @Test
    func enableERGClampsToSupportedRange() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 10)        // below 50
        await controller.enableERG(targetWatts: 1_000)     // above 500

        #expect(bike.ergCalls == [50, 500])
        #expect(controller.currentTargetWatts == 500)
    }

    @Test
    func adjustTargetSetsStickyOverride() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 200)
        await controller.adjustTargetWatts(by: 5)

        #expect(controller.currentTargetWatts == 205)
        #expect(controller.ergUserOverridden == true)
        #expect(bike.setPowerCalls == [205])
    }

    @Test
    func reEnablingERGClearsStickyOverride() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 150)
        await controller.adjustTargetWatts(by: 10)
        #expect(controller.ergUserOverridden == true)

        await controller.enableERG(targetWatts: 200)
        #expect(controller.ergUserOverridden == false)
        #expect(controller.currentTargetWatts == 200)
    }

    @Test
    func controlPermissionLostFlipsToControlLost() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)
        await controller.enableERG(targetWatts: 200)

        bike.statusSubject.send(.controlPermissionLost)
        await wait()

        #expect(controller.mode == .off)
        #expect(controller.lastError == .controlLost)
        #expect(controller.currentTargetWatts == nil)
    }

    @Test
    func pauseCallsStopOrPause() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.pause()
        #expect(bike.stopOrPauseCalls == [true])
    }

    @Test
    func resumeReissuesLastERGTarget() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 220)
        await controller.resume()

        #expect(bike.setPowerCalls == [220])
    }

    @Test
    func resetClearsStateAndCallsBike() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 180)
        await controller.adjustTargetWatts(by: 5)
        await controller.reset()

        #expect(bike.resetCalls == 1)
        #expect(controller.mode == .off)
        #expect(controller.currentTargetWatts == nil)
        #expect(controller.ergUserOverridden == false)
    }

    @Test
    func capabilitiesUpdateOnPublisher() async {
        let bike = MockFTMSBike(capabilities: nil)
        let controller = LiveTrainerController(bike: bike)
        #expect(controller.capabilities == nil)

        bike.updateCapabilities(defaultCapabilities())
        await wait()

        #expect(controller.capabilities?.powerTargetSettingSupported == true)
    }

    @Test
    func enterErgErrorMapsToTrainerError() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        bike.enterErgError = FTMSError.controlPointError(.controlNotPermitted)
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 200)

        #expect(controller.lastError == .controlLost)
    }

    // MARK: - Level mode

    @Test
    func setResistanceLevelClampsToSupportedRange() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.setResistanceLevel(-5)     // below 0
        await controller.setResistanceLevel(200)    // above 100

        #expect(bike.setResistanceCalls == [0, 100])
        #expect(controller.currentResistanceLevel == 100)
    }

    @Test
    func setResistanceLevelTransitionsFromERGToManualResistance() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.enableERG(targetWatts: 200)
        #expect(controller.mode == .erg)

        await controller.setResistanceLevel(40)

        #expect(controller.mode == .manualResistance)
        #expect(controller.currentResistanceLevel == 40)
        // currentTargetWatts cleared so the ERG readout doesn't show a stale value.
        #expect(controller.currentTargetWatts == nil)
    }

    // MARK: - Simulation mode

    /// Drive a `LiveTrainerController` against a controllable clock so the
    /// 1Hz throttle is deterministic.
    private final class Clock: @unchecked Sendable {
        var now: Date = Date(timeIntervalSince1970: 1_000_000)
        func advance(by seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    @MainActor
    private func makeSimController(_ clock: Clock) -> (MockFTMSBike, LiveTrainerController) {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike, dateProvider: { clock.now })
        return (bike, controller)
    }

    @Test
    func enterSimulationSendsInitialParams() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 5.0)

        #expect(bike.simParamCalls.count == 1)
        let call = bike.simParamCalls[0]
        #expect(call.wind == 0)
        #expect(call.grade == 5.0)
        #expect(abs(call.crr - GPXParser.defaultCrr) < 0.0001)
        #expect(abs(call.cw - GPXParser.defaultCw) < 0.0001)
        #expect(controller.mode == .simulation)
        #expect(controller.currentGradePercent == 5.0)
        // Fresh-into-sim must still issue the request-control + start
        // handshake — otherwise the trainer can ignore the sim params
        // until something else nudges it into a controlled mode.
        #expect(bike.requestControlCalls == 1)
        #expect(bike.startCalls == 1)
    }

    @Test
    func enterSimulationStopsTrainerWhenLeavingERG() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)
        await controller.enableERG(targetWatts: 200)
        #expect(controller.mode == .erg)

        await controller.enterSimulation(initialGrade: 3)

        // Stop must precede the sim-params write — Wahoo / Tacx trainers
        // otherwise keep holding the ERG power target after the mode change.
        #expect(bike.stopOrPauseCalls == [false])
        #expect(controller.mode == .simulation)
        #expect(controller.currentTargetWatts == nil)
    }

    @Test
    func setGradeIsNoOpWhenNotInSimulationMode() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.setGrade(3.0)
        #expect(bike.simParamCalls.isEmpty)
        #expect(controller.currentGradePercent == nil)
    }

    @Test
    func setGradeThrottlesSmallDeltasInsideOneSecondWindow() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 5.0)
        #expect(bike.simParamCalls.count == 1)

        // 10 rapid calls, 100ms apart, each with a tiny delta — only the
        // initial enter should be on record afterwards.
        for _ in 0..<10 {
            clock.advance(by: 0.1)
            await controller.setGrade(5.05)
        }
        #expect(bike.simParamCalls.count == 1)
    }

    @Test
    func setGradeAlwaysSendsLargeDeltas() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 5.0)
        clock.advance(by: 0.1)
        // Delta of 2% ≥ simWriteImmediateDelta (1.0) — should bypass throttle.
        await controller.setGrade(7.0)
        #expect(bike.simParamCalls.count == 2)
        #expect(bike.simParamCalls.last?.grade == 7.0)
    }

    @Test
    func setGradeSendsAfterThrottleWindow() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 5.0)
        // 0.5% delta — small enough to throttle, but after >1s should go through.
        clock.advance(by: 1.5)
        await controller.setGrade(5.5)
        #expect(bike.simParamCalls.count == 2)
    }

    @Test
    func setGradeClampsToTwentyPercent() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 100)
        #expect(bike.simParamCalls.last?.grade == 20)
        #expect(controller.currentGradePercent == 20)

        clock.advance(by: 2)
        await controller.setGrade(-50)
        #expect(bike.simParamCalls.last?.grade == -20)
        #expect(controller.currentGradePercent == -20)
    }

    @Test
    func enterSimulationOpcodeNotSupportedSurfacesError() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)
        bike.setSimParamError = FTMSError.controlPointError(.opcodeNotSupported)

        await controller.enterSimulation(initialGrade: 5)

        #expect(controller.mode == .off)
        #expect(controller.lastError == .opcodeNotSupported)
        #expect(controller.currentGradePercent == nil)
    }

    @Test
    func resumeReissuesLastGradeInSimulation() async {
        let clock = Clock()
        let (bike, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 8.0)
        let before = bike.simParamCalls.count
        await controller.resume()
        #expect(bike.simParamCalls.count == before + 1)
        #expect(bike.simParamCalls.last?.grade == 8.0)
    }

    @Test
    func resetClearsSimulationState() async {
        let clock = Clock()
        let (_, controller) = makeSimController(clock)

        await controller.enterSimulation(initialGrade: 4)
        await controller.reset()
        #expect(controller.mode == .off)
        #expect(controller.currentGradePercent == nil)
    }

    @Test
    func enableERGFromManualResistanceFlipsModeBack() async {
        let bike = MockFTMSBike(capabilities: defaultCapabilities())
        let controller = LiveTrainerController(bike: bike)

        await controller.setResistanceLevel(50)
        #expect(controller.mode == .manualResistance)

        await controller.enableERG(targetWatts: 175)

        #expect(controller.mode == .erg)
        #expect(controller.currentTargetWatts == 175)
        // Resistance level is left in place — it's still the trainer's last
        // known value if the user nudges back to Level mode; ERG only governs
        // the active control path, not the cached resistance.
        #expect(controller.currentResistanceLevel == 50)
    }
}
