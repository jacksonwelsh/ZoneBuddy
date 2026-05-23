import Testing
import Foundation
import CoreLocation
import HealthKit
import FTMSKit
@testable import ZoneBuddy

@MainActor
struct WorkoutPlayerViewModelTests {
    private func wait() async {
        // Wait long enough for the Task to process the tick and update the MainActor state
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func makeIntervals() -> [Interval] {
        [
            Interval(zone: .zone2, duration: 5, sortOrder: 0),
            Interval(zone: .zone4, duration: 10, sortOrder: 1),
            Interval(zone: .zone1, duration: 3, sortOrder: 2),
        ]
    }

    @Test
    func initialState() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)

        #expect(vm.currentIntervalIndex == 0)
        #expect(vm.secondsRemaining == 5)
        #expect(vm.isRunning == false)
        #expect(vm.isFinished == false)
        #expect(vm.currentLabel == "Endurance")
        #expect(vm.currentZoneNumber == 2)
    }

    @Test
    func startBeginsTimer() async {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)

        vm.start()
        
        // Give the task a moment to start and request ticks
        await wait()

        #expect(vm.isRunning == true)
        #expect(timer.timerStarted == true)
    }

    @Test
    func tickCountsDown() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime }
        )
        
        vm.start()
        await wait()
        
        // Advance time and fire tick
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        
        // Wait for VM to process
        await wait()

        #expect(vm.secondsRemaining == 4)
        #expect(vm.totalElapsedSeconds == 1)
    }

    @Test
    func advancesToNextInterval() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime }
        )
        
        vm.start()
        await wait()

        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.currentIntervalIndex == 1)
        #expect(vm.secondsRemaining == 10)
        #expect(vm.currentLabel == "Threshold")
    }

    @Test
    func transitionBannerShows() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 15, sortOrder: 0),
            Interval(zone: .zone5, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            transitionWarningDuration: 10,
            dateProvider: { currentTime }
        )
        
        vm.start()
        await wait()
        
        // 4 seconds elapsed => 11 remaining, no banner
        currentTime.addTimeInterval(4)
        timer.fire(at: currentTime)
        await wait()
        #expect(vm.showTransitionBanner == false)

        // 5 seconds elapsed => 10 remaining, banner shows
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()
        #expect(vm.showTransitionBanner == true)
        #expect(vm.upcomingLabel == "VO2 Max")
    }

    @Test
    func transitionBannerHidesOnAdvance() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 12, sortOrder: 0),
            Interval(zone: .zone5, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime }
        )
        
        vm.start()
        await wait()

        currentTime.addTimeInterval(12)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.showTransitionBanner == false)
        #expect(vm.currentIntervalIndex == 1)
    }

    @Test
    func workoutFinishes() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        // Total: 5 + 10 + 3 = 18 ticks
        currentTime.addTimeInterval(18)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.isFinished == true)
        #expect(vm.isRunning == false)
        #expect(vm.totalElapsedSeconds == 18)
    }

    @Test
    func naturalFinishThenDoneTapPersistsOnce() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let persister = CountingSessionPersister()
        let healthKit = MockHealthKitWorkoutRecorder()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            healthKitManager: healthKit,
            sessionPersister: persister
        )

        vm.start()
        await wait()

        // Run the workout to completion via the timer loop (natural finish path).
        currentTime.addTimeInterval(18)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.isFinished == true)
        #expect(persister.saveCount == 1)

        // Simulate the user tapping "Done" on the completion screen — this must NOT
        // persist a second session or the workout shows up twice in history.
        vm.endWorkout()
        await wait()

        #expect(persister.saveCount == 1)
    }

    @Test
    func pauseAndResume() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime }
        )
        
        vm.start()
        await wait()

        currentTime.addTimeInterval(2)
        timer.fire(at: currentTime)
        await wait()
        
        vm.pause()
        #expect(vm.isRunning == false)
        #expect(vm.secondsRemaining == 3)

        // Advance "real" time while paused
        currentTime.addTimeInterval(100)
        
        vm.resume()
        await wait()
        
        // Fire 1 second after resume
        currentTime.addTimeInterval(1)
        timer.fire(at: currentTime)
        await wait()
        
        #expect(vm.isRunning == true)
        #expect(vm.totalElapsedSeconds == 3) // 2 before + 1 after
        #expect(vm.secondsRemaining == 2)
    }

    @Test
    func intervalProgress() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone3, duration: 10, sortOrder: 0),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()
        #expect(vm.intervalProgress == 0.0)

        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()
        #expect(vm.intervalProgress == 0.5)
    }

    // MARK: - Speech Cue Tests

    @Test
    func startAnnouncesFirstZone() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let speech = MockSpeechCueProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            speechCueProvider: speech,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        #expect(speech.spokenTexts == ["Zone 2 for 5 seconds"])
    }

    @Test
    func intervalAdvanceSpeaksNewZone() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let speech = MockSpeechCueProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            speechCueProvider: speech,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(speech.spokenTexts == ["Zone 2 for 5 seconds", "Zone 4 for 10 seconds"])
    }

    // MARK: - Music Playback Tests

    @Test
    func startBeginsPlayback() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let music = MockMusicPlaybackManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            musicPlaybackManager: music,
            playlistID: "pl.abc123",
            playlistShuffle: true,
            playlistRepeat: false,
            playlistAutoMix: true
        )

        vm.start()
        await wait()

        #expect(music.startCalled == true)
        #expect(music.startPlaylistID == "pl.abc123")
        #expect(music.startShuffle == true)
        #expect(music.startRepeatMode == false)
        #expect(music.startAutoMix == true)
    }

    @Test
    func pauseStopsPlayback() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let music = MockMusicPlaybackManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            musicPlaybackManager: music,
            playlistID: "pl.abc123"
        )

        vm.start()
        await wait()
        vm.pause()

        #expect(music.pauseCalled == true)
    }

    @Test
    func resumeResumesPlayback() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let music = MockMusicPlaybackManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            musicPlaybackManager: music,
            playlistID: "pl.abc123"
        )

        vm.start()
        await wait()
        vm.pause()

        currentTime.addTimeInterval(5)
        vm.resume()
        await wait()

        #expect(music.resumeCalled == true)
    }

    @Test
    func workoutFinishStopsPlayback() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let music = MockMusicPlaybackManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            musicPlaybackManager: music,
            playlistID: "pl.abc123"
        )

        vm.start()
        await wait()

        currentTime.addTimeInterval(18)
        timer.fire(at: currentTime)
        await wait()

        #expect(music.stopCalled == true)
    }

    @Test
    func noMusicWithoutPlaylistID() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let music = MockMusicPlaybackManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            musicPlaybackManager: music
        )

        vm.start()
        await wait()

        #expect(music.startCalled == false)
    }

    @Test
    func noSpeechWhenAudioCuesDisabled() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let speech = MockSpeechCueProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            speechCueProvider: speech,
            dateProvider: { currentTime }
        )

        vm.audioCuesEnabled = false
        vm.start()
        await wait()

        #expect(speech.spokenTexts.isEmpty)
    }

    // MARK: - FTP Computed Property Tests

    @Test
    func currentFTPReturnsSettingsValue() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        #expect(vm.currentFTP == SettingsManager.shared.functionalThresholdPower)
    }

    @Test
    func targetPowerRangeNilDuringWarmup() {
        let timer = MockTimerProvider()
        let intervals = [Interval.warmup(duration: 60, sortOrder: 0)]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        #expect(vm.targetPowerRange == nil)
        #expect(vm.targetRangeDescription == nil)
    }

    @Test
    func targetPowerRangeValidDuringZone() {
        let timer = MockTimerProvider()
        let intervals = [Interval(zone: .zone4, duration: 60, sortOrder: 0)]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        #expect(vm.targetPowerRange != nil)
        #expect(vm.targetRangeDescription != nil)
        #expect(vm.targetRangeDescription!.hasSuffix("W"))
    }

    @Test
    func powerAsPercentOfFTPNilWithoutBike() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        #expect(vm.powerAsPercentOfFTP == nil)
        #expect(vm.actualPowerZone == nil)
    }

    @Test
    func stopClearsActiveSpeech() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let speech = MockSpeechCueProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            speechCueProvider: speech,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        // Finish the workout
        currentTime.addTimeInterval(18)
        timer.fire(at: currentTime)
        await wait()

        #expect(speech.stopCalled == true)
    }

    // MARK: - ERG / Trainer Integration

    @Test
    func startEnablesERGAtZoneMidpointWhenFirstIntervalIsNotWarmup() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),                 // first interval: Z2 (Endurance)
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)        // Z2 = 55–74% → 110–148W → mid ~ 129W
        )

        vm.start()
        await wait()

        let fake = bike.fakeTrainer
        #expect(fake.mode == .erg)
        let target = fake.currentTargetWatts ?? 0
        // Midpoint of Z2 [110, 148] = 129. Allow a one-watt fudge for integer rounding.
        #expect(abs(target - 129) <= 1)
    }

    @Test
    func warmupParksTrainerInLevelZeroThenERGEngagesOnExit() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let intervals = [
            Interval.warmup(duration: 5, sortOrder: 0),
            Interval(zone: .zone3, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)
        )

        vm.start()
        await wait()

        let fake = bike.fakeTrainer
        // Warmup → drop into Level mode at level 0 so the rider can spin freely.
        #expect(fake.mode == .manualResistance)
        #expect(fake.currentResistanceLevel == 0)
        #expect(fake.currentTargetWatts == nil)

        // Advance past the warmup → next interval is Z3, ERG should engage.
        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(fake.mode == .erg)
        // Z3 = 75–89% of 200 → 150–178 → mid ~ 164.
        let target = fake.currentTargetWatts ?? 0
        #expect(abs(target - 164) <= 1)
    }

    @Test
    func warmupExitForcesERGEvenIfRiderAdjustedLevel() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let intervals = [
            Interval.warmup(duration: 5, sortOrder: 0),
            Interval(zone: .zone3, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)
        )

        vm.start()
        await wait()

        let fake = bike.fakeTrainer
        #expect(fake.mode == .manualResistance)

        // Rider nudges the resistance up during warmup. Crossing into the
        // active interval should still snap them into ERG — Level 0 was our
        // auto-applied warmup default, not an opt-out.
        await fake.setResistanceLevel(25)
        #expect(fake.currentResistanceLevel == 25)

        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(fake.mode == .erg)
        let target = fake.currentTargetWatts ?? 0
        #expect(abs(target - 164) <= 1)
    }

    @Test
    func manualOverrideBlocksIntervalTransitionTargets() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let intervals = [
            Interval(zone: .zone3, duration: 5, sortOrder: 0),
            Interval(zone: .zone5, duration: 5, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)
        )

        vm.start()
        await wait()

        let fake = bike.fakeTrainer
        let initialTarget = fake.currentTargetWatts

        // User nudges via the trainer-adjust pathway
        vm.applyTrainerTarget(absoluteWatts: (initialTarget ?? 0) + 10)
        await wait()
        #expect(fake.ergUserOverridden == true)
        #expect(fake.currentTargetWatts == (initialTarget ?? 0) + 10)

        // Cross interval boundary — controller should NOT receive a new midpoint target.
        let afterOverride = fake.currentTargetWatts
        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(fake.currentTargetWatts == afterOverride)
    }

    // MARK: - Free Ride

    @Test
    func freeRideNoGoalNeverFinishesNaturally() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            mode: .freeRide(goal: nil)
        )

        vm.start()
        await wait()
        #expect(vm.isRunning == true)

        currentTime.addTimeInterval(600)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.isFinished == false)
        #expect(vm.totalElapsedSeconds == 600)
    }

    @Test
    func freeRideTimeGoalFinishesWhenGoalReached() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            mode: .freeRide(goal: .time(seconds: 30))
        )

        #expect(vm.secondsRemaining == 30)

        vm.start()
        await wait()

        currentTime.addTimeInterval(10)
        timer.fire(at: currentTime)
        await wait()
        #expect(vm.isFinished == false)
        #expect(vm.secondsRemaining == 20)

        currentTime.addTimeInterval(20)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.isFinished == true)
        #expect(vm.totalElapsedSeconds == 30)
        #expect(vm.secondsRemaining == 0)
    }

    @Test
    func freeRideAccumulatesActualZoneTime() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        // FTP 200W. Z3 = 150–178W, mid 165. We'll feed 165W → actualPowerZone = .zone3.
        let bike = FreeRideStubBikeManager(power: 165)
        let persister = CountingSessionPersister()
        let healthKit = MockHealthKitWorkoutRecorder()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            settings: FixedFTPSettings(ftp: 200),
            sessionPersister: persister,
            mode: .freeRide(goal: .time(seconds: 5))
        )

        vm.start()
        await wait()

        // Tick 5 times (1 second each)
        for i in 1...5 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
            _ = i
        }

        #expect(vm.isFinished == true)
        // Persisted session should hold the actual time-in-zone breakdown.
        guard let saved = persister.lastSession else {
            Issue.record("Expected a persisted session")
            return
        }
        #expect(saved.modality == .freeRide)
        // We ticked at seconds 1..5. The tick at second 5 hits the goal-reached branch and exits
        // BEFORE accumulating; only ticks 1..4 record zone time. That's 4 seconds in Z3.
        #expect(saved.scheduledSecondsByZone[.zone3] == 4)
        // On-target tracking should remain empty for free ride.
        #expect(saved.onTargetSecondsByZone.values.allSatisfy { $0 == 0 })
    }

    @Test
    func freeRidePersistsWithIsFreeRideTrueAndEmptyIntervals() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let persister = CountingSessionPersister()
        let healthKit = MockHealthKitWorkoutRecorder()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            workoutName: "Free Ride",
            dateProvider: { currentTime },
            healthKitManager: healthKit,
            sessionPersister: persister,
            mode: .freeRide(goal: nil)
        )

        vm.start()
        await wait()

        currentTime.addTimeInterval(60)
        timer.fire(at: currentTime)
        await wait()

        // No-goal free ride doesn't finish on its own — the user ends it.
        vm.endWorkout()
        await wait()

        #expect(persister.saveCount == 1)
        guard let saved = persister.lastSession else {
            Issue.record("Expected a persisted session")
            return
        }
        #expect(saved.modality == .freeRide)
        #expect(saved.name == "Free Ride")
        #expect((saved.intervals ?? []).isEmpty)
        #expect(saved.totalDuration == 60)
    }

    @Test
    func freeRideSkipsAutoERG() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200),
            mode: .freeRide(goal: nil)
        )

        vm.start()
        await wait()

        // Auto-ERG must not engage in free ride — there's no prescribed zone.
        #expect(bike.fakeTrainer.mode == .off)
        #expect(bike.fakeTrainer.currentTargetWatts == nil)
    }

    @Test
    func levelModeBlocksAutoERGAtIntervalBoundary() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let intervals = [
            Interval(zone: .zone2, duration: 5, sortOrder: 0),
            Interval(zone: .zone4, duration: 5, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)
        )

        vm.start()
        await wait()

        let fake = bike.fakeTrainer
        // Sanity: ERG kicked in for the first non-warmup interval.
        #expect(fake.mode == .erg)

        // User switches into Level mode mid-workout.
        await fake.setResistanceLevel(40)
        #expect(fake.mode == .manualResistance)

        // Cross into interval 2. Auto-ERG must NOT pull us back into ERG.
        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(vm.currentIntervalIndex == 1)
        #expect(fake.mode == .manualResistance)
        #expect(fake.currentResistanceLevel == 40)
    }

    @Test
    func reEnableERGClearsOverrideAndSnapsToCurrentZoneMidpoint() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = StubTrainerBikeManager()
        let intervals = [Interval(zone: .zone3, duration: 30, sortOrder: 0)]
        let vm = WorkoutPlayerViewModel(
            intervals: intervals,
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            settings: FixedFTPSettings(ftp: 200)
        )

        vm.start()
        await wait()
        let baseline = bike.fakeTrainer.currentTargetWatts ?? 0
        vm.applyTrainerTarget(absoluteWatts: baseline + 25)
        await wait()
        #expect(bike.fakeTrainer.ergUserOverridden == true)

        vm.reEnableERGForCurrentInterval()
        await wait()

        #expect(bike.fakeTrainer.ergUserOverridden == false)
        let target = bike.fakeTrainer.currentTargetWatts ?? 0
        #expect(abs(target - 164) <= 1) // Z3 midpoint at FTP 200
    }

    // MARK: - Route ride / HealthKit route helpers

    /// Synthetic 1km route with a flat → climb → descent profile and a straight
    /// northward lat/lon trace. Mirrors the controller test fixture so HK route
    /// metadata assertions exercise the same shape.
    private func makeRouteFixture() -> Route {
        var pts: [RoutePoint] = []
        let step = 5.0
        let startLat = 37.0
        let endLat = 37.01
        for i in 0...200 {
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
            let lat = startLat + (endLat - startLat) * (d / 1000.0)
            pts.append(RoutePoint(distanceMeters: d, elevationMeters: ele, gradePercent: grade, latitude: lat, longitude: -122.0))
        }
        return Route(name: "Test Route", points: pts)
    }

    @Test
    func routeRideStartCallsBeginRouteRecording() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FreeRideStubBikeManager(power: 200)
        let healthKit = MockHealthKitWorkoutRecorder()
        let route = makeRouteFixture()
        let controller = RouteProgressionController(
            route: route,
            trainerController: nil,
            bikeManager: bike,
            dateProvider: { currentTime }
        )

        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            shouldPersistSession: false,
            mode: .routeRide(routeID: route.id),
            routeController: controller
        )

        vm.start()
        // requestAuthorization → startWorkout → beginRouteRecording is a three-hop chain.
        await wait()
        await wait()

        #expect(healthKit.didBeginRouteRecording == true)
    }

    @Test
    func scheduledRideDoesNotCallBeginRouteRecording() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let healthKit = MockHealthKitWorkoutRecorder()

        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            dateProvider: { currentTime },
            healthKitManager: healthKit,
            shouldPersistSession: false
        )

        vm.start()
        await wait()
        await wait()

        #expect(healthKit.didBeginRouteRecording == false)
    }

    @Test
    func routeRideEndPublishesLocationsAndElevationMetadata() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let bike = FreeRideStubBikeManager(power: 200)
        let healthKit = MockHealthKitWorkoutRecorder()
        let route = makeRouteFixture()
        let controller = RouteProgressionController(
            route: route,
            trainerController: nil,
            bikeManager: bike,
            dateProvider: { currentTime }
        )

        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            shouldPersistSession: false,
            mode: .routeRide(routeID: route.id),
            routeController: controller
        )

        vm.start()
        await wait()
        await wait()

        // Drive 5 ticks of forward motion — virtual speed at 200W on a flat
        // grade is several m/s, so distance advances and locations accumulate.
        for _ in 0..<5 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
        }

        vm.endWorkout()
        // Final drain + endWorkout Task chain.
        await wait()
        await wait()

        #expect(healthKit.addedRouteLocations.count >= 2)
        // First emitted location should sit on the route's starting coordinate.
        if let first = healthKit.addedRouteLocations.first {
            #expect(abs(first.coordinate.latitude - 37.0) < 1e-4)
            #expect(abs(first.coordinate.longitude - (-122.0)) < 1e-9)
            #expect(first.horizontalAccuracy > 0)
            #expect(first.verticalAccuracy > 0)
        }

        // Metadata must carry HKQuantity-typed elevation keys + route name/ID,
        // otherwise HealthKit rejects the workout's metadata write.
        #expect(healthKit.lastMetadata[HKMetadataKeyElevationAscended] is HKQuantity)
        #expect(healthKit.lastMetadata[HKMetadataKeyElevationDescended] is HKQuantity)
        #expect((healthKit.lastMetadata["ZoneBuddyRouteName"] as? String) == "Test Route")
        #expect((healthKit.lastMetadata["ZoneBuddyRouteID"] as? String) == route.id.uuidString)
    }

    @Test
    func routeRideStationaryEmitsAtMostStartLocation() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        // Power=nil forces the controller off the virtual-speed path (whose
        // cubic root finder converges to a tiny non-zero value at P=0) and
        // onto the trainer-speed fallback. Trainer speed = 0 km/h → no advance.
        let bike = FreeRideStubBikeManager(power: 0)
        bike.latestBikeData = BikeData(
            instantaneousSpeed: 0,
            instantaneousCadence: 0,
            instantaneousPower: nil,
            timestamp: Date()
        )
        let healthKit = MockHealthKitWorkoutRecorder()
        let route = makeRouteFixture()
        let controller = RouteProgressionController(
            route: route,
            trainerController: nil,
            bikeManager: bike,
            dateProvider: { currentTime }
        )

        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            dateProvider: { currentTime },
            bikeManager: bike,
            healthKitManager: healthKit,
            shouldPersistSession: false,
            mode: .routeRide(routeID: route.id),
            routeController: controller
        )

        vm.start()
        await wait()
        await wait()

        // Several ticks without movement — the distance-advanced gate must
        // suppress duplicates so we don't stack identical locations.
        for _ in 0..<6 {
            currentTime.addTimeInterval(1)
            timer.fire(at: currentTime)
            await wait()
        }

        vm.endWorkout()
        await wait()
        await wait()

        // Exactly one location: the start sample emitted on the first tick
        // (snap.distanceMeters=0 > sentinel=-1). Every subsequent tick fails
        // the gate (0 > 0 is false).
        #expect(healthKit.addedRouteLocations.count == 1)
    }
}

// MARK: - Test helpers

@MainActor
@Observable
private final class StubTrainerBikeManager: BikeConnecting {
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

@MainActor
@Observable
private final class FreeRideStubBikeManager: BikeConnecting {
    var isConnected: Bool = true
    var connectedBikeName: String? = "Stub Bike"
    var latestBikeData: BikeData?
    var discoveredDevices: [FTMSDiscoveredDevice] = []
    var isScanning: Bool = false
    var accumulatedSamples: [BikeDataSample] = []
    var hasReceivedNonZeroMetric: Bool = true
    var isReconnecting: Bool = false
    var trainerController: (any TrainerControlling)? { nil }

    init(power: Int) {
        self.latestBikeData = BikeData(
            instantaneousSpeed: 30,
            instantaneousCadence: 90,
            instantaneousPower: power,
            timestamp: Date()
        )
    }

    func startScanning() {}
    func stopScanning() {}
    func connect(to device: FTMSDiscoveredDevice) {}
    func disconnect() {}
    func drainSamples() -> [BikeDataSample] { [] }
    func autoConnect(timeout: TimeInterval) {}
    func attemptReconnect() {}
}

private final class FixedFTPSettings: SettingsReading {
    var functionalThresholdPower: Int
    var maxHeartRate: Int = 190
    var audioCuesEnabled: Bool = false
    var transitionWarningDuration: Int = 10
    init(ftp: Int) {
        self.functionalThresholdPower = ftp
    }
}
