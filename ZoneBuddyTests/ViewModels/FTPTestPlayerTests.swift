import Testing
import Foundation
import FTMSKit
@testable import ZoneBuddy

@MainActor
struct FTPTestPlayerTests {
    private func wait() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - ergTargetWattsForCurrentInterval

    @Test
    func ergTargetPrefersExplicitTargetWattsOverZoneMidpoint() {
        let intervals = [Interval(zone: .zone3, duration: 60, sortOrder: 0, targetWatts: 275)]
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            settings: FixedFTPSettings(ftp: 200)
        )

        // Explicit target wins (275), not the Z3 midpoint at FTP 200 (~164).
        #expect(vm.ergTargetWattsForCurrentInterval == 275)
    }

    @Test
    func ergTargetFallsBackToZoneMidpointWhenNoExplicitTarget() {
        let intervals = [Interval(zone: .zone3, duration: 60, sortOrder: 0)]
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            settings: FixedFTPSettings(ftp: 200)
        )

        let midpoint = vm.ergTargetWattsForCurrentInterval ?? 0
        #expect(abs(midpoint - 164) <= 1) // Z3 midpoint at FTP 200
    }

    @Test
    func ergTargetNilForWarmupWithoutExplicitTarget() {
        let intervals = [Interval(zone: nil, duration: 60, sortOrder: 0)]
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            settings: FixedFTPSettings(ftp: 200)
        )

        #expect(vm.ergTargetWattsForCurrentInterval == nil)
    }

    // MARK: - 20-min FTP test ERG safety

    @Test
    func twentyMinFTPTestDisablesERGOnStart() async {
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        // Simulate a trainer that was left locked in ERG from a prior workout.
        await bike.fakeTrainer.enableERG(targetWatts: 220)
        #expect(bike.fakeTrainer.mode == .erg)

        let vm = WorkoutPlayerViewModel(
            intervals: FTPTestProtocol.makeIntervals(),
            timerProvider: timer,
            bikeManager: bike,
            ftpTestKind: .twentyMinute
        )

        vm.start()
        await wait()

        // ERG must be released before the rider starts the test — locking watts
        // during a max-effort would produce the cadence/resistance spiral of death.
        #expect(bike.fakeTrainer.mode == .off)
        #expect(bike.fakeTrainer.currentTargetWatts == nil)
    }

    @Test
    func twentyMinFTPTestDoesNotEnableERGAtTransitions() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()

        // Short clone of the FTP protocol so a test tick can advance phases.
        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 1, sortOrder: 1),
            Interval(zone: nil, duration: 1, sortOrder: 2),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            ftpTestKind: .twentyMinute
        )

        vm.start()
        await wait()
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()

        // Even after transitioning into the test interval, ERG stays off.
        #expect(bike.fakeTrainer.mode == .off)
    }

    // MARK: - Ramp test drives explicit targets via ERG

    @Test
    func rampTestEnablesERGAtRampStepWithExplicitTarget() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()

        // Three intervals: a 1-sec warmup, a 1-sec ramp step at 150W, end.
        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 1, sortOrder: 1, targetWatts: 150),
            Interval(zone: nil, duration: 1, sortOrder: 2),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            ftpTestKind: .ramp
        )

        vm.start()
        await wait()
        // Warmup parks the trainer in Level mode at 0 (no power target).
        #expect(bike.fakeTrainer.mode == .manualResistance)
        #expect(bike.fakeTrainer.currentResistanceLevel == 0)
        #expect(bike.fakeTrainer.currentTargetWatts == nil)

        // Advance into the ramp step.
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()

        #expect(bike.fakeTrainer.mode == .erg)
        #expect(bike.fakeTrainer.currentTargetWatts == 150)
    }

    @Test
    func rampStepTargetWattsSurfacesCurrentTarget() {
        let intervals = [
            Interval(zone: nil, duration: 60, sortOrder: 0, targetWatts: 220),
        ]
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            ftpTestKind: .ramp
        )

        #expect(vm.rampStepTargetWatts == 220)
    }

    @Test
    func rampTestSkipsToCooldownOnSustainedLowCadence() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 90,
            instantaneousPower: 150,
            timestamp: currentTime
        )

        // 1-sec warmup, 30-sec ramp step at 150W, 300-sec cooldown.
        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 30, sortOrder: 1, targetWatts: 150),
            Interval(zone: nil, duration: 300, sortOrder: 2),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            ftpTestKind: .ramp
        )

        vm.start()
        await wait()

        // Advance into the ramp step. ERG engages.
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()
        #expect(bike.fakeTrainer.mode == .erg)
        #expect(vm.currentIntervalIndex == 1)

        // Drop cadence well below the failure threshold and tick through the
        // grace window + the three confirmation ticks.
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 35,
            instantaneousPower: 150,
            timestamp: currentTime
        )

        for _ in 0..<8 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
            if vm.currentIntervalIndex == 2 { break }
        }

        // Failure should land the rider in the cooldown interval, not end the
        // workout, and the trainer should be released from ERG so the rider
        // can spin easy.
        #expect(vm.currentIntervalIndex == 2)
        #expect(vm.isFinished == false)
        #expect(vm.isRunning == true)
        #expect(bike.fakeTrainer.mode == .off)
        #expect(vm.secondsRemaining > 0)
    }

    @Test
    func rampTestDoesNotAutoEndIfCadenceRecovers() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 90,
            instantaneousPower: 150,
            timestamp: currentTime
        )

        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 60, sortOrder: 1, targetWatts: 150),
            Interval(zone: nil, duration: 1, sortOrder: 2),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            ftpTestKind: .ramp
        )

        vm.start()
        await wait()
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()

        // Burn the grace window with normal cadence so the failure check is live.
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 90,
            instantaneousPower: 150,
            timestamp: currentTime
        )
        for _ in 0..<6 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
        }

        // Two ticks below threshold — not yet three consecutive.
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 35,
            instantaneousPower: 150,
            timestamp: currentTime
        )
        for _ in 0..<2 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
        }

        // Cadence recovers — counter must reset, test continues.
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 90,
            instantaneousPower: 150,
            timestamp: currentTime
        )
        for _ in 0..<5 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
        }

        #expect(vm.isFinished == false)
    }

    // MARK: - History persistence

    @Test
    func twentyMinFTPTestPersistsModalityWithResult() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        let persister = CountingSessionPersister()
        let healthKit = MockHealthKitWorkoutRecorder()

        // 1-sec warmup, 2-sec test interval, 1-sec end. Index 1 == testIntervalIndex
        // for the 20-min protocol, so the test interval drives FTP sampling.
        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 2, sortOrder: 1),
            Interval(zone: nil, duration: 1, sortOrder: 2),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            workoutName: "FTP Test",
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            ftpTestKind: .twentyMinute,
            sessionPersister: persister
        )

        vm.start()
        await wait()

        // Tick to t=1 — workout transitions into the test interval, so
        // ftpTestStartedAt is captured.
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()

        // Queue power samples timestamped inside the test window so the
        // end-of-workout drain pulls them into allBikeSamples before
        // finalizeFTPTestResult runs.
        bike.pendingSamples = [
            BikeDataSample(timestamp: currentTime.addingTimeInterval(0.5), power: 200, cadence: nil, heartRate: nil, speed: nil, distance: nil, calories: nil),
            BikeDataSample(timestamp: currentTime.addingTimeInterval(1.5), power: 200, cadence: nil, heartRate: nil, speed: nil, distance: nil, calories: nil),
        ]

        // Tick past the end to finish the workout naturally.
        currentTime.addTimeInterval(4)
        timer.fire(at: currentTime)
        await wait()

        guard let saved = persister.lastSession else {
            Issue.record("Expected a persisted session")
            return
        }
        guard case .ftpTest(let proto, let result) = saved.modality else {
            Issue.record("Expected .ftpTest modality, got \(saved.modality)")
            return
        }
        #expect(proto == .twentyMinute)
        // 20-min FTP = round(0.95 × avg). With two 200W samples, avg = 200,
        // FTP = round(190.0) = 190.
        #expect(result?.measuredFTP == 190)
        #expect(result?.sourcePower == 200)
    }

    @Test
    func ftpTestPersistsModalityEvenWithoutResult() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        let persister = CountingSessionPersister()
        let healthKit = MockHealthKitWorkoutRecorder()

        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 1, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            workoutName: "FTP Ramp Test",
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            ftpTestKind: .ramp,
            sessionPersister: persister
        )

        vm.start()
        await wait()
        // No bike samples — test ends with no power data, so no result.
        currentTime.addTimeInterval(3)
        timer.fire(at: currentTime)
        await wait()

        guard let saved = persister.lastSession else {
            Issue.record("Expected a persisted session")
            return
        }
        guard case .ftpTest(let proto, let result) = saved.modality else {
            Issue.record("Expected .ftpTest modality, got \(saved.modality)")
            return
        }
        #expect(proto == .ramp)
        #expect(result == nil)
    }

    // MARK: - SessionModality round-trip

    @Test
    func sessionModalityRoundTripsThroughCodable() throws {
        let cases: [SessionModality] = [
            .structured,
            .freeRide,
            .ftpTest(protocol: .twentyMinute, result: FTPTestResult(measuredFTP: 245, sourcePower: 258)),
            .ftpTest(protocol: .ramp, result: FTPTestResult(measuredFTP: 255, sourcePower: 340)),
            .ftpTest(protocol: .ramp, result: nil),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for value in cases {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(SessionModality.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test
    func sessionWithoutModalityJSONFallsBackToStructured() {
        let session = WorkoutSession(name: "Workout", totalDuration: 600)
        #expect(session.modality == .structured)
    }

    @Test
    func sessionConstructedAsFreeRideHasFreeRideModality() {
        let session = WorkoutSession(name: "Free Ride", totalDuration: 600, modality: .freeRide)
        #expect(session.modality == .freeRide)
    }

    @Test
    func sessionConstructedAsFTPTestHasFTPTestModality() {
        let session = WorkoutSession(
            name: "FTP Test",
            totalDuration: 1200,
            modality: .ftpTest(
                protocol: .twentyMinute,
                result: FTPTestResult(measuredFTP: 245, sourcePower: 258)
            )
        )
        guard case .ftpTest(let proto, let result) = session.modality else {
            Issue.record("Expected .ftpTest modality")
            return
        }
        #expect(proto == .twentyMinute)
        #expect(result?.measuredFTP == 245)
        #expect(result?.sourcePower == 258)
    }

    @Test
    func rampStepTargetWattsNilForTwentyMinTest() {
        let intervals = [Interval(zone: nil, duration: 60, sortOrder: 0, targetWatts: 220)]
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            ftpTestKind: .twentyMinute
        )

        // Even if an interval carries targetWatts, the 20-min test doesn't surface it
        // (the 20-min protocol doesn't use explicit targets).
        #expect(vm.rampStepTargetWatts == nil)
    }
}

// MARK: - Test helpers

private final class FixedFTPSettings: SettingsReading {
    var functionalThresholdPower: Int
    var maxHeartRate: Int = 190
    var audioCuesEnabled: Bool = false
    var transitionWarningDuration: Int = 10
    init(ftp: Int) {
        self.functionalThresholdPower = ftp
    }
}

@MainActor
@Observable
private final class FTPTestStubBikeManager: BikeConnecting {
    var isConnected: Bool = true
    var connectedBikeName: String? = "Stub Trainer"
    var latestBikeData: BikeData? = nil
    var discoveredDevices: [FTMSDiscoveredDevice] = []
    var isScanning: Bool = false
    var accumulatedSamples: [BikeDataSample] = []
    var hasReceivedNonZeroMetric: Bool = true
    var isReconnecting: Bool = false

    /// Samples returned (and cleared) by the next `drainSamples()` call. Tests
    /// queue power samples here to drive the FTP calculation end-to-end.
    var pendingSamples: [BikeDataSample] = []

    let fakeTrainer = FakeTrainerController()
    var trainerController: (any TrainerControlling)? { fakeTrainer }

    func startScanning() {}
    func stopScanning() {}
    func connect(to device: FTMSDiscoveredDevice) {}
    func disconnect() {}
    func drainSamples() -> [BikeDataSample] {
        let drained = pendingSamples
        pendingSamples = []
        return drained
    }
    func autoConnect(timeout: TimeInterval) {}
    func attemptReconnect() {}
}
