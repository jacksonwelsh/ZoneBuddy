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
}
