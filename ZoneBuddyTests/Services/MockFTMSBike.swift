import Foundation
import Combine
import FTMSKit
@testable import ZoneBuddy

/// In-process double of an FTMS bike for `LiveTrainerController` unit tests.
/// Records every control-point call and lets a test push `MachineStatus`
/// notifications through the publisher to exercise the controller's reactions.
@MainActor
final class MockFTMSBike: FTMSBikeControlling {
    var currentCapabilities: TrainerCapabilities?
    let capabilitiesSubject = CurrentValueSubject<TrainerCapabilities?, Never>(nil)
    let statusSubject = PassthroughSubject<MachineStatus, Never>()

    var capabilitiesPublisher: AnyPublisher<TrainerCapabilities?, Never> {
        capabilitiesSubject.eraseToAnyPublisher()
    }
    var machineStatusPublisher: AnyPublisher<MachineStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    // Call log
    private(set) var ergCalls: [Int] = []
    private(set) var setPowerCalls: [Int] = []
    private(set) var setResistanceCalls: [Double] = []
    private(set) var stopOrPauseCalls: [Bool] = []
    private(set) var resetCalls: Int = 0

    // Configurable failures
    var enterErgError: Error?
    var setPowerError: Error?

    init(capabilities: TrainerCapabilities? = nil) {
        self.currentCapabilities = capabilities
        self.capabilitiesSubject.send(capabilities)
    }

    func updateCapabilities(_ caps: TrainerCapabilities?) {
        currentCapabilities = caps
        capabilitiesSubject.send(caps)
    }

    func enterErgMode(targetWatts: Int) async throws {
        if let enterErgError { throw enterErgError }
        ergCalls.append(targetWatts)
    }

    func setTargetPower(_ watts: Int) async throws {
        if let setPowerError { throw setPowerError }
        setPowerCalls.append(watts)
    }

    func setTargetResistanceLevel(_ level: Double) async throws {
        setResistanceCalls.append(level)
    }

    func stopOrPause(pause: Bool) async throws {
        stopOrPauseCalls.append(pause)
    }

    func reset() async throws {
        resetCalls += 1
    }
}
