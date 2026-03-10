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

    // MARK: - Live Activity Tests

    @Test
    func startBeginsLiveActivity() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr,
            workoutName: "Test Ride",
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        #expect(activityMgr.startCalled == true)
        #expect(activityMgr.startAttributes?.workoutName == "Test Ride")
        #expect(activityMgr.startAttributes?.totalIntervals == 3)
        #expect(activityMgr.startState?.currentLabel == "Endurance")
        #expect(activityMgr.startState?.isRunning == true)
        #expect(activityMgr.startState?.intervalEndDate != nil)
    }

    @Test
    func pauseUpdatesActivityWithNilEndDate() async {
        let currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        vm.pause()
        await wait()

        #expect(activityMgr.lastUpdateState?.intervalEndDate == nil)
        #expect(activityMgr.lastUpdateState?.isRunning == false)
    }

    @Test
    func resumeUpdatesActivityWithEndDate() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        vm.pause()

        currentTime.addTimeInterval(50)
        vm.resume()
        await wait()

        #expect(activityMgr.lastUpdateState?.intervalEndDate != nil)
        #expect(activityMgr.lastUpdateState?.isRunning == true)
    }

    @Test
    func intervalAdvanceUpdatesActivity() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        let updateCountBefore = activityMgr.updateCallCount

        currentTime.addTimeInterval(5)
        timer.fire(at: currentTime)
        await wait()

        #expect(activityMgr.updateCallCount > updateCountBefore)
        #expect(activityMgr.lastUpdateState?.currentLabel == "Threshold")
        #expect(activityMgr.lastUpdateState?.currentIntervalIndex == 1)
    }

    @Test
    func workoutFinishEndsActivity() async {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr,
            dateProvider: { currentTime }
        )

        vm.start()
        await wait()

        currentTime.addTimeInterval(18)
        timer.fire(at: currentTime)
        await wait()

        #expect(activityMgr.endCalled == true)
        #expect(activityMgr.endState?.isFinished == true)
        #expect(activityMgr.endDismissalBehavior == .afterDelay(120))
    }

    @Test
    func endActivityCalledOnDismiss() async {
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: makeIntervals(),
            timerProvider: timer,
            activityManager: activityMgr
        )

        vm.start()
        await wait()

        vm.pause()
        await wait()
        vm.endActivity()
        await wait()

        #expect(activityMgr.endCalled == true)
        #expect(activityMgr.endDismissalBehavior == .immediate)
    }

    @Test
    func noActivityStartedForEmptyIntervals() {
        let timer = MockTimerProvider()
        let activityMgr = MockActivityManager()
        let vm = WorkoutPlayerViewModel(
            intervals: [],
            timerProvider: timer,
            activityManager: activityMgr
        )

        vm.start()

        #expect(activityMgr.startCalled == false)
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
}
