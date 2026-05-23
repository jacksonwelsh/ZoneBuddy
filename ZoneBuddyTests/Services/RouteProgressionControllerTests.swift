import Testing
import Foundation
import FTMSKit
@testable import ZoneBuddy

@MainActor
struct RouteProgressionControllerTests {

    // MARK: - Test doubles

    @Observable
    fileprivate final class MockTrainer: TrainerControlling {
        private(set) var mode: TrainerMode = .off
        var capabilities: TrainerCapabilities?
        private(set) var currentTargetWatts: Int?
        private(set) var currentResistanceLevel: Double?
        private(set) var currentGradePercent: Double?
        var lastError: TrainerError?
        private(set) var ergUserOverridden: Bool = false

        private(set) var enterSimulationCalls: [Double] = []
        private(set) var setGradeCalls: [Double] = []

        func enableERG(targetWatts: Int) async {}
        func disableERG() async {}
        func setTargetWatts(_ watts: Int) async {}
        func adjustTargetWatts(by delta: Int) async {}
        func setResistanceLevel(_ level: Double) async {}
        func enterSimulation(initialGrade: Double) async {
            mode = .simulation
            currentGradePercent = initialGrade
            enterSimulationCalls.append(initialGrade)
        }
        func setGrade(_ percent: Double) async {
            currentGradePercent = percent
            setGradeCalls.append(percent)
        }
        func pause() async {}
        func resume() async {}
        func reset() async {
            mode = .off
            currentGradePercent = nil
        }
    }

    @Observable
    fileprivate final class MockBike: BikeConnecting {
        var isConnected: Bool = true
        var connectedBikeName: String? = "Mock"
        var latestBikeData: BikeData?
        var discoveredDevices: [FTMSDiscoveredDevice] = []
        var isScanning: Bool = false
        var accumulatedSamples: [BikeDataSample] = []
        var hasReceivedNonZeroMetric: Bool = true
        var isReconnecting: Bool = false
        var trainerController: (any TrainerControlling)?

        func setSpeed(_ kmh: Double) {
            latestBikeData = BikeData(instantaneousSpeed: kmh)
        }

        func startScanning() {}
        func stopScanning() {}
        func connect(to device: FTMSDiscoveredDevice) {}
        func disconnect() {}
        func drainSamples() -> [BikeDataSample] { [] }
        func autoConnect(timeout: TimeInterval) {}
        func attemptReconnect() {}
    }

    private final class Clock: @unchecked Sendable {
        var now: Date = Date(timeIntervalSince1970: 1_000_000)
        func advance(by seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    // MARK: - Helpers

    /// Build a synthetic 3-segment route: flat 300m → 5% climb to 700m → -3% descent to 1000m.
    /// Lat/lon trace a straight northward line so `currentPosition()` interpolation
    /// is testable: distance 0 → (37.0, -122.0), distance 1000m → (37.01, -122.0).
    private func makeTestRoute() -> Route {
        var pts: [RoutePoint] = []
        let step = 5.0
        let totalDistance = 1000.0
        let startLat = 37.0
        let endLat = 37.01
        let lon = -122.0
        for i in 0...200 {  // 1000m / 5m = 200
            let d = Double(i) * step
            let grade: Double
            let ele: Double
            if d < 300 {
                grade = 0
                ele = 100
            } else if d < 700 {
                grade = 5
                ele = 100 + (d - 300) * 0.05
            } else {
                grade = -3
                ele = 120 - (d - 700) * 0.03
            }
            let lat = startLat + (endLat - startLat) * (d / totalDistance)
            pts.append(RoutePoint(distanceMeters: d, elevationMeters: ele, gradePercent: grade, latitude: lat, longitude: lon))
        }
        return Route(name: "Test", points: pts)
    }

    /// Drain queued `Task { await ... }` blocks so the trainer call log
    /// reflects calls scheduled by the latest tick.
    private func drainTasks() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - Tests

    @Test
    func beginEntersSimulationAtStartingGrade() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike
        )
        await controller.begin()
        #expect(trainer.enterSimulationCalls == [0])  // first segment is flat
        #expect(trainer.mode == .simulation)
    }

    @Test
    func firstTickHasNoBaselineAndDoesNotMove() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)  // 10 m/s
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        // First tick — no previous tick, so integrate 0.
        controller.tick(now: clock.now)
        #expect(controller.distanceMeters == 0)
    }

    @Test
    func integratesSpeedIntoDistanceAndCrossesSegments() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)  // 36 km/h = 10 m/s
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)  // baseline only

        // 10 ticks of 1s each at 10 m/s → 100m traveled.
        for _ in 0..<10 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
        }
        await drainTasks()

        #expect(abs(controller.distanceMeters - 100) < 1)
        #expect(controller.currentGradePercent == 0)  // still in the flat segment
        #expect(!trainer.setGradeCalls.isEmpty)
    }

    @Test
    func gradeMatchesPositionAfterCrossingIntoClimb() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)  // 10 m/s
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        // Need to cover ~500m total to reach mid-climb (300m flat + 200m climb).
        for _ in 0..<50 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
        }
        await drainTasks()
        #expect(controller.distanceMeters >= 400)
        #expect(controller.currentGradePercent == 5)
    }

    @Test
    func elevationGainAccumulatesOnClimb() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        // 70 ticks of 1s @ 10 m/s = 700m → finishes the climb, gain ≈ 20m.
        for _ in 0..<70 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
        }
        await drainTasks()
        #expect(controller.elevationGainMeters > 18 && controller.elevationGainMeters < 22)
    }

    @Test
    func pauseClearsBaselineSoResumeTickDoesNotIntegrate() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        clock.advance(by: 1)
        controller.tick(now: clock.now)
        let distAfterFirst = controller.distanceMeters
        #expect(distAfterFirst > 0)

        controller.pause()
        // A long pause — without baseline reset this would integrate as movement.
        clock.advance(by: 60)
        controller.resume()
        controller.tick(now: clock.now)
        // Should be unchanged from before the pause (the first post-resume
        // tick re-establishes the baseline without integrating).
        #expect(controller.distanceMeters == distAfterFirst)
    }

    @Test
    func reachingEndFinishesAndSendsZeroGrade() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(100)  // Fast — finish quickly.
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        // 100 km/h = 27.8 m/s. 1000m / 27.8 = ~36 ticks of 1s.
        for _ in 0..<60 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
            if controller.isFinished { break }
        }
        await drainTasks()
        #expect(controller.isFinished)
        #expect(controller.distanceMeters == controller.route.totalDistanceMeters)
        #expect(trainer.setGradeCalls.contains(0))
    }

    @Test
    func progressFractionRangesZeroToOne() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        #expect(controller.progressFraction == 0)
        await controller.begin()
        controller.tick(now: clock.now)
        for _ in 0..<50 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
        }
        #expect(controller.progressFraction > 0 && controller.progressFraction < 1)
    }

    @Test
    func elevationLossAccumulatesOnDescent() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        // Ride to the end (~100 ticks @ 10 m/s = 1000m). Descent segment is
        // 700→1000m at -3%, so loss ≈ 9m.
        for _ in 0..<120 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
            if controller.isFinished { break }
        }
        await drainTasks()
        #expect(controller.elevationLossMeters > 7 && controller.elevationLossMeters < 11)
    }

    @Test
    func elevationGainAndLossTrackIndependently() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(36)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        for _ in 0..<120 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
            if controller.isFinished { break }
        }
        await drainTasks()
        // Climb segment 300→700m at +5% climbs 20m. Descent 700→1000m at -3% drops 9m.
        #expect(controller.elevationGainMeters > 18 && controller.elevationGainMeters < 22)
        #expect(controller.elevationLossMeters > 7 && controller.elevationLossMeters < 11)
    }

    @Test
    func currentPositionBeforeAdvanceReturnsStart() {
        let trainer = MockTrainer()
        let bike = MockBike()
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike
        )
        guard let snap = controller.currentPosition() else {
            Issue.record("Expected a snapshot at start")
            return
        }
        #expect(snap.distanceMeters == 0)
        #expect(abs(snap.latitude - 37.0) < 1e-9)
        #expect(abs(snap.longitude - (-122.0)) < 1e-9)
        #expect(abs(snap.elevationMeters - 100) < 1e-9)
    }

    @Test
    func currentPositionInterpolatesLatLonBetweenPoints() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(18)  // 5 m/s — fine-grained advance
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        // Advance 500m total — lat should land halfway between 37.0 and 37.01 = 37.005.
        for _ in 0..<100 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
        }
        await drainTasks()
        guard let snap = controller.currentPosition() else {
            Issue.record("Expected a snapshot mid-route")
            return
        }
        #expect(abs(snap.distanceMeters - 500) < 1)
        // Linear lat interp: at 500m, lat = 37.0 + 0.5 * 0.01 = 37.005.
        #expect(abs(snap.latitude - 37.005) < 1e-4)
        #expect(abs(snap.longitude - (-122.0)) < 1e-9)
    }

    @Test
    func currentPositionAtRouteEndClampsToFinalPoint() async {
        let trainer = MockTrainer()
        let bike = MockBike()
        let clock = Clock()
        bike.setSpeed(100)
        let controller = RouteProgressionController(
            route: makeTestRoute(),
            trainerController: trainer,
            bikeManager: bike,
            dateProvider: { clock.now }
        )
        await controller.begin()
        controller.tick(now: clock.now)
        for _ in 0..<60 {
            clock.advance(by: 1)
            controller.tick(now: clock.now)
            if controller.isFinished { break }
        }
        await drainTasks()
        guard let snap = controller.currentPosition() else {
            Issue.record("Expected a snapshot at finish")
            return
        }
        #expect(controller.isFinished)
        #expect(snap.distanceMeters == controller.route.totalDistanceMeters)
        // Final route point sits at lat = 37.01.
        #expect(abs(snap.latitude - 37.01) < 1e-9)
    }
}
