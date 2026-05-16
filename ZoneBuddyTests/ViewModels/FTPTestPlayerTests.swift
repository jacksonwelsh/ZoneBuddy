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
        // Warmup interval should not push a target.
        #expect(bike.fakeTrainer.mode == .off)

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
    func rampTestAutoEndsOnSustainedLowCadence() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FTPTestStubBikeManager()
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 90,
            instantaneousPower: 150,
            timestamp: currentTime
        )

        // 1-sec warmup, 30-sec ramp step at 150W, end.
        let intervals = [
            Interval(zone: nil, duration: 1, sortOrder: 0),
            Interval(zone: nil, duration: 30, sortOrder: 1, targetWatts: 150),
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

        // Advance into the ramp step. ERG engages.
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()
        #expect(bike.fakeTrainer.mode == .erg)
        #expect(vm.isFinished == false)

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
            if vm.isFinished { break }
        }

        #expect(vm.isFinished == true)
        #expect(vm.isRunning == false)
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

    let fakeTrainer = FakeTrainerController()
    var trainerController: (any TrainerControlling)? { fakeTrainer }

    func startScanning() {}
    func stopScanning() {}
    func connect(to device: FTMSDiscoveredDevice) {}
    func disconnect() {}
    func drainSamples() -> [BikeDataSample] { [] }
    func autoConnect(timeout: TimeInterval) {}
    func attemptReconnect() {}
}
