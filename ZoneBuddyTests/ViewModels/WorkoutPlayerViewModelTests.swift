import Testing
@testable import ZoneBuddy

@MainActor
struct WorkoutPlayerViewModelTests {
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
        #expect(vm.currentLabel == "Zone 2")
        #expect(vm.currentZoneNumber == 2)
    }

    @Test
    func startBeginsTimer() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)

        vm.start()

        #expect(vm.isRunning == true)
        #expect(timer.timerStarted == true)
    }

    @Test
    func tickCountsDown() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()

        timer.fire(times: 1)

        #expect(vm.secondsRemaining == 4)
        #expect(vm.totalElapsedSeconds == 1)
    }

    @Test
    func advancesToNextInterval() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()

        timer.fire(times: 5)

        #expect(vm.currentIntervalIndex == 1)
        #expect(vm.secondsRemaining == 10)
        #expect(vm.currentLabel == "Zone 4")
    }

    @Test
    func transitionBannerShows() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 15, sortOrder: 0),
            Interval(zone: .zone5, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()

        // 4 ticks => 11 remaining, no banner
        timer.fire(times: 4)
        #expect(vm.showTransitionBanner == false)

        // 1 more tick => 10 remaining, banner shows
        timer.fire(times: 1)
        #expect(vm.showTransitionBanner == true)
        #expect(vm.upcomingLabel == "Zone 5")
    }

    @Test
    func transitionBannerHidesOnAdvance() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 12, sortOrder: 0),
            Interval(zone: .zone5, duration: 10, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()

        timer.fire(times: 12)

        #expect(vm.showTransitionBanner == false)
        #expect(vm.currentIntervalIndex == 1)
    }

    @Test
    func noBannerOnLastInterval() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 5, sortOrder: 0),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()

        timer.fire(times: 3)
        #expect(vm.showTransitionBanner == false)
    }

    @Test
    func workoutFinishes() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()

        // Total: 5 + 10 + 3 = 18 ticks
        timer.fire(times: 18)

        #expect(vm.isFinished == true)
        #expect(vm.isRunning == false)
        #expect(vm.totalElapsedSeconds == 18)
    }

    @Test
    func cooldownLabel() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()

        // Advance to last interval (5 + 10 = 15 ticks)
        timer.fire(times: 15)

        #expect(vm.currentIntervalIndex == 2)
        #expect(vm.currentLabel == "Cooldown")
    }

    @Test
    func pauseAndResume() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()

        timer.fire(times: 2)
        vm.pause()

        #expect(vm.isRunning == false)
        #expect(vm.secondsRemaining == 3)

        vm.resume()
        #expect(vm.isRunning == true)
    }

    @Test
    func togglePlayPause() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: makeIntervals(), timerProvider: timer)
        vm.start()
        #expect(vm.isRunning == true)

        vm.togglePlayPause()
        #expect(vm.isRunning == false)

        vm.togglePlayPause()
        #expect(vm.isRunning == true)
    }

    @Test
    func emptyIntervalsDoesNotCrash() {
        let timer = MockTimerProvider()
        let vm = WorkoutPlayerViewModel(intervals: [], timerProvider: timer)

        vm.start()
        #expect(vm.isRunning == false)
        #expect(vm.currentInterval == nil)
    }

    @Test
    func warmupLabel() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval.warmup(duration: 60, sortOrder: 0),
            Interval(zone: .zone3, duration: 30, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)

        #expect(vm.currentLabel == "Warmup")
        #expect(vm.currentZoneNumber == nil)
    }

    @Test
    func intervalProgress() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone3, duration: 10, sortOrder: 0),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()

        #expect(vm.intervalProgress == 0.0)

        timer.fire(times: 5)
        #expect(vm.intervalProgress == 0.5)

        timer.fire(times: 4)
        #expect(vm.intervalProgress == 0.9)
    }

    @Test
    func resumeAfterFinishDoesNothing() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone2, duration: 2, sortOrder: 0),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()
        timer.fire(times: 2)

        #expect(vm.isFinished == true)

        vm.resume()
        #expect(vm.isRunning == false)
    }

    @Test
    func upcomingCooldownLabel() {
        let timer = MockTimerProvider()
        let intervals = [
            Interval(zone: .zone3, duration: 12, sortOrder: 0),
            Interval(zone: .zone1, duration: 60, sortOrder: 1),
        ]
        let vm = WorkoutPlayerViewModel(intervals: intervals, timerProvider: timer)
        vm.start()

        // Tick to trigger banner
        timer.fire(times: 5)
        #expect(vm.upcomingLabel == "Cooldown")
    }
}
