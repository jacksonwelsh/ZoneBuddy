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
        if interval.isWarmup { return "Warmup" }
        if isLastInterval && interval.zone == .zone1 { return "Cooldown" }
        return interval.zone?.displayName ?? ""
    }

    var currentZoneNumber: Int? {
        currentInterval?.zone?.rawValue
    }

    var upcomingLabel: String {
        guard let next = nextInterval else { return "" }
        if next.isWarmup { return "Warmup" }
        let nextIndex = currentIntervalIndex + 1
        let isNextLast = nextIndex == intervals.count - 1
        if isNextLast && next.zone == .zone1 { return "Cooldown" }
        return next.zone?.displayName ?? ""
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
    private var timerCancellable: TimerCancellable?
    private let transitionWarningSeconds: Int = 10

    // MARK: - Init

    init(intervals: [Interval], timerProvider: TimerProviding) {
        self.intervals = intervals
        self.timerProvider = timerProvider
        if let first = intervals.first {
            self.secondsRemaining = first.duration
        }
    }

    deinit {
        timerCancellable?.cancel()
    }

    // MARK: - Actions

    func start() {
        guard !intervals.isEmpty else { return }
        isRunning = true
        startTimer()
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func resume() {
        guard !isFinished else { return }
        isRunning = true
        startTimer()
    }

    func togglePlayPause() {
        if isRunning {
            pause()
        } else {
            resume()
        }
    }

    // MARK: - Timer Logic

    private func startTimer() {
        timerCancellable?.cancel()
        timerCancellable = timerProvider.scheduledTimer(interval: 1.0) { [self] in
            self.tick()
        }
    }

    func tick() {
        guard isRunning, !isFinished else { return }

        totalElapsedSeconds += 1
        secondsRemaining -= 1

        if secondsRemaining <= transitionWarningSeconds && nextInterval != nil {
            showTransitionBanner = true
        } else {
            showTransitionBanner = false
        }

        if secondsRemaining <= 0 {
            advanceToNextInterval()
        }
    }

    private func advanceToNextInterval() {
        showTransitionBanner = false

        let nextIndex = currentIntervalIndex + 1
        if nextIndex < intervals.count {
            currentIntervalIndex = nextIndex
            secondsRemaining = intervals[nextIndex].duration
        } else {
            isRunning = false
            isFinished = true
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }
}
