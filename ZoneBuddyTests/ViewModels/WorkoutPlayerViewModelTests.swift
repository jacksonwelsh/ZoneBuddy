import Testing
import Foundation
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
        #expect(vm.currentLabel == "Zone 2")
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
        #expect(vm.currentLabel == "Zone 4")
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
        #expect(vm.upcomingLabel == "Zone 5")
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
}
