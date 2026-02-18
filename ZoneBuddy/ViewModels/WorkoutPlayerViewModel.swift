import SwiftUI

@Observable
final class WorkoutPlayerViewModel {
    // MARK: - State

    private(set) var currentIntervalIndex: Int = 0
    private(set) var secondsRemaining: Int = 0
    private(set) var totalElapsedSeconds: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var showTransitionBanner: Bool = false
    var showTimer: Bool = true
    var audioCuesEnabled: Bool = SettingsManager.shared.audioCuesEnabled

    // MARK: - Computed

    var currentInterval: Interval? {
        guard currentIntervalIndex < intervals.count else { return nil }
        return intervals[currentIntervalIndex]
    }

    var nextInterval: Interval? {
        let nextIndex = currentIntervalIndex + 1
        guard nextIndex < intervals.count else { return nil }
        return intervals[nextIndex]
    }

    var currentZoneColor: Color {
        currentInterval?.zone?.color ?? Color.gray
    }

    var currentForegroundColor: Color {
        currentInterval?.zone?.foregroundColor ?? .white
    }

    var currentLabel: String {
        guard let interval = currentInterval else { return "" }
        if isLastInterval && interval.zone == .zone1 { return "Cooldown" }
        return interval.baseLabel
    }

    var currentZoneNumber: Int? {
        currentInterval?.zone?.rawValue
    }

    var upcomingLabel: String {
        guard let next = nextInterval else { return "" }
        let nextIndex = currentIntervalIndex + 1
        let isNextLast = nextIndex == intervals.count - 1
        if isNextLast && next.zone == .zone1 { return "Cooldown" }
        return next.baseLabel
    }

    var upcomingZoneColor: Color {
        nextInterval?.zone?.color ?? Color.gray
    }

    var intervalProgress: Double {
        guard let interval = currentInterval, interval.duration > 0 else { return 0 }
        let elapsed = interval.duration - secondsRemaining
        return Double(elapsed) / Double(interval.duration)
    }

    var isLastInterval: Bool {
        currentIntervalIndex == intervals.count - 1
    }

    // MARK: - Private

    let intervals: [Interval]
    private let timerProvider: TimerProviding
    private let activityManager: ActivityManaging
    private let speechCueProvider: SpeechCueProviding
    private let workoutName: String
    private let transitionWarningDuration: Int
    private let spokenDurationSecondsThreshold: Int = 90
    private let dateProvider: @Sendable () -> Date

    private var timerTask: Task<Void, Never>?
    private var workoutStartDate: Date?
    private var totalSecondsAccumulatedBeforePause: TimeInterval = 0
    private var activityHasStarted: Bool = false

    // MARK: - Init

    init(
        intervals: [Interval],
        timerProvider: TimerProviding,
        activityManager: ActivityManaging = LiveActivityManager(),
        speechCueProvider: SpeechCueProviding = LiveSpeechCueProvider(),
        workoutName: String = "",
        transitionWarningDuration: Int = 10,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.intervals = intervals
        self.timerProvider = timerProvider
        self.activityManager = activityManager
        self.speechCueProvider = speechCueProvider
        self.workoutName = workoutName
        self.transitionWarningDuration = transitionWarningDuration
        self.dateProvider = dateProvider
        if let first = intervals.first {
            self.secondsRemaining = first.duration
        }
    }

    deinit {
        timerTask?.cancel()
        speechCueProvider.stop()
    }

    // MARK: - Actions

    func start() {
        guard !isRunning && !isFinished && !intervals.isEmpty else { return }

        workoutStartDate = dateProvider()
        isRunning = true

        if !activityHasStarted {
            activityHasStarted = true
            let attributes = WorkoutActivityAttributes(
                workoutName: workoutName,
                totalIntervals: intervals.count
            )
            speakCurrentLabel()
            activityManager.startActivity(attributes: attributes, state: makeContentState())
        } else {
            activityManager.updateActivity(state: makeContentState())
        }

        timerTask?.cancel()
        timerTask = Task { @MainActor in
            let ticker = timerProvider.ticks(every: .seconds(1))

            for await currentTime in ticker {
                if Task.isCancelled || !isRunning { break }
                guard let startDate = workoutStartDate else { break }

                let segmentElapsed = currentTime.timeIntervalSince(startDate)
                let totalElapsed = segmentElapsed + totalSecondsAccumulatedBeforePause

                let previousIndex = self.currentIntervalIndex
                self.totalElapsedSeconds = Int(totalElapsed)
                self.recalculateIntervalState(totalElapsed: totalElapsed)

                if self.isFinished {
                    self.activityManager.endActivity(
                        state: self.makeContentState(),
                        dismissalBehavior: .afterDelay(60)
                    )
                    stopWorkout()
                    break
                }

                if self.currentIntervalIndex != previousIndex {
                    self.speakCurrentLabel()
                    self.activityManager.updateActivity(state: self.makeContentState())
                }
            }
        }
    }

    func pause() {
        guard isRunning else { return }

        if let startDate = workoutStartDate {
            totalSecondsAccumulatedBeforePause += dateProvider().timeIntervalSince(startDate)
        }

        isRunning = false
        workoutStartDate = nil
        timerTask?.cancel()
        timerTask = nil

        if activityHasStarted {
            activityManager.updateActivity(state: makeContentState())
        }
    }

    func resume() {
        start()
    }

    func togglePlayPause() {
        if isRunning {
            pause()
        } else {
            resume()
        }
    }

    private func stopWorkout() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        workoutStartDate = nil
        speechCueProvider.stop()
    }

    func startBackgroundKeepAlive() {
        speechCueProvider.startBackgroundKeepAlive()
    }

    func stopBackgroundKeepAlive() {
        speechCueProvider.stopBackgroundKeepAlive()
    }

    func recalculateOnForeground() {
        guard isRunning, let startDate = workoutStartDate else { return }
        let segmentElapsed = dateProvider().timeIntervalSince(startDate)
        let totalElapsed = segmentElapsed + totalSecondsAccumulatedBeforePause
        totalElapsedSeconds = Int(totalElapsed)
        recalculateIntervalState(totalElapsed: totalElapsed)
        activityManager.updateActivity(state: makeContentState())
    }

    func endActivity() {
        guard activityHasStarted else { return }
        activityManager.endActivity(state: makeContentState(), dismissalBehavior: .immediate)
        activityHasStarted = false
    }

    // MARK: - Activity State

    private func makeContentState() -> WorkoutActivityAttributes.ContentState {
        .init(
            currentZoneRawValue: currentInterval?.zone?.rawValue,
            currentLabel: currentLabel,
            currentIntervalIndex: currentIntervalIndex,
            nextZoneRawValue: nextInterval?.zone?.rawValue,
            upcomingLabel: upcomingLabel,
            intervalStartDate: isRunning ? dateProvider().addingTimeInterval(TimeInterval(secondsRemaining - (currentInterval?.duration ?? 0))) : nil,
            intervalEndDate: isRunning ? dateProvider().addingTimeInterval(TimeInterval(secondsRemaining)) : nil,
            secondsRemaining: secondsRemaining,
            intervalProgress: intervalProgress,
            isRunning: isRunning,
            isFinished: isFinished
        )
    }

    private func speakCurrentLabel() {
        guard audioCuesEnabled else { return }
        let label = currentLabel
        guard !label.isEmpty else { return }

        if let interval = currentInterval {
            let durationText = spokenDuration(seconds: interval.duration)
            speechCueProvider.speak("\(label) for \(durationText)")
        } else {
            speechCueProvider.speak(label)
        }
    }

    private func spokenDuration(seconds: Int) -> String {
        if seconds <= spokenDurationSecondsThreshold {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = seconds / 60
        let remainderSeconds = seconds % 60
        let minutePart = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if remainderSeconds == 0 {
            return minutePart
        }
        let secondPart = remainderSeconds == 1 ? "1 second" : "\(remainderSeconds) seconds"
        return "\(minutePart) \(secondPart)"
    }

    private func recalculateIntervalState(totalElapsed: TimeInterval) {
        var timeMarker: TimeInterval = 0

        for (index, interval) in intervals.enumerated() {
            let intervalDuration = TimeInterval(interval.duration)
            let intervalEnd = timeMarker + intervalDuration

            if totalElapsed < intervalEnd {
                currentIntervalIndex = index
                secondsRemaining = Int(ceil(intervalEnd - totalElapsed))

                showTransitionBanner = (secondsRemaining <= transitionWarningDuration && index < intervals.count - 1)
                return
            }
            timeMarker = intervalEnd
        }

        isFinished = true
        isRunning = false
        secondsRemaining = 0
    }
}
