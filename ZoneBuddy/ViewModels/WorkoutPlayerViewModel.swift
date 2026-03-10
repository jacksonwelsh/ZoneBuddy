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

    var upcomingZoneNumber: Int? {
        nextInterval?.zone?.rawValue
    }

    var upcomingForegroundColor: Color {
        nextInterval?.zone?.foregroundColor ?? .white
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
    private let musicPlaybackManager: MusicPlaybackManaging?
    private let workoutName: String
    private let transitionWarningDuration: Int
    private let spokenDurationSecondsThreshold: Int = 90
    private let dateProvider: @Sendable () -> Date
    private let playlistID: String?
    private let playlistKind: String?
    private let playlistShuffle: Bool
    private let playlistRepeat: Bool
    private let playlistAutoMix: Bool

    private var timerTask: Task<Void, Never>?
    private var pushTokenPollTask: Task<Void, Never>?
    private var workoutStartDate: Date?
    private var totalSecondsAccumulatedBeforePause: TimeInterval = 0
    private var activityHasStarted: Bool = false
    private var serverWorkoutId: String?

    private static let apiSecret: String =
        Bundle.main.infoDictionary?["ZoneBuddyAPISecret"] as? String ?? ""

    #if DEBUG
    private static let serverBaseURL: String = {
        let url = Bundle.main.infoDictionary?["ZoneBuddyDevServerURL"] as? String ?? ""
        return url.isEmpty ? "http://localhost:8787" : url
    }()
    #else
    private static let serverBaseURL = "https://zonebuddy-worker.jacksn.dev"
    #endif

    // MARK: - Init

    init(
        intervals: [Interval],
        timerProvider: TimerProviding,
        activityManager: ActivityManaging = LiveActivityManager(),
        speechCueProvider: SpeechCueProviding = LiveSpeechCueProvider(),
        workoutName: String = "",
        transitionWarningDuration: Int = 10,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        musicPlaybackManager: MusicPlaybackManaging? = nil,
        playlistID: String? = nil,
        playlistKind: String? = nil,
        playlistShuffle: Bool = false,
        playlistRepeat: Bool = false,
        playlistAutoMix: Bool = false
    ) {
        self.intervals = intervals
        self.timerProvider = timerProvider
        self.activityManager = activityManager
        self.speechCueProvider = speechCueProvider
        self.musicPlaybackManager = musicPlaybackManager
        self.workoutName = workoutName
        self.transitionWarningDuration = transitionWarningDuration
        self.dateProvider = dateProvider
        self.playlistID = playlistID
        self.playlistKind = playlistKind
        self.playlistShuffle = playlistShuffle
        self.playlistRepeat = playlistRepeat
        self.playlistAutoMix = playlistAutoMix
        if let first = intervals.first {
            self.secondsRemaining = first.duration
        }
    }

    deinit {
        timerTask?.cancel()
        pushTokenPollTask?.cancel()
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
            activityManager.startActivity(attributes: attributes, state: makeContentState())
            pollForPushTokenAndRegister()
            startMusicPlayback()
            speakCurrentLabel(delay: musicPlaybackManager != nil)
        } else {
            activityManager.updateActivity(state: makeContentState())
            reregisterAfterPause()
            musicPlaybackManager?.resumePlayback()
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
                        dismissalBehavior: .afterDelay(120)
                    )
                    self.pushTokenPollTask?.cancel()
                    self.pushTokenPollTask = nil
                    // Server sends its own end push; cancel to avoid duplicates
                    self.cancelServerWorkout()
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

        // Stop polling and cancel the server-side workout so it stops sending pushes.
        pushTokenPollTask?.cancel()
        pushTokenPollTask = nil
        cancelServerWorkout()

        musicPlaybackManager?.pausePlayback()

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
        musicPlaybackManager?.stopPlayback()
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
        pushTokenPollTask?.cancel()
        pushTokenPollTask = nil
        cancelServerWorkout()
    }

    // MARK: - Music Playback

    private func startMusicPlayback() {
        guard let musicPlaybackManager, let playlistID else { return }
        Task {
            await musicPlaybackManager.startPlayback(
                playlistID: playlistID,
                kind: playlistKind,
                shuffle: playlistShuffle,
                repeatMode: playlistRepeat,
                autoMix: playlistAutoMix
            )
        }
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

    private func speakCurrentLabel(delay: Bool = false) {
        guard audioCuesEnabled else { return }
        guard let interval = currentInterval else { return }
        let spokenLabel: String
        if isLastInterval && interval.zone == .zone1 {
            spokenLabel = "Cooldown"
        } else {
            spokenLabel = interval.spokenLabel
        }
        guard !spokenLabel.isEmpty else { return }

        let text: String
        let durationText = spokenDuration(seconds: interval.duration)
        text = "\(spokenLabel) for \(durationText)"

        if delay {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                speechCueProvider.speak(text)
            }
        } else {
            speechCueProvider.speak(text)
        }
    }

    private func spokenDuration(seconds: Int) -> String {
        if seconds <= 90 {
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

    // MARK: - Server Communication

    private func reregisterAfterPause() {
        // Capture paused state synchronously before the async task can observe a tick.
        let fromIndex = currentIntervalIndex
        let pausedSecondsRemaining = secondsRemaining
        let startTime = dateProvider().timeIntervalSince1970

        pushTokenPollTask?.cancel()
        pushTokenPollTask = Task { @MainActor in
            // The Live Activity is already running so the token should be available immediately.
            var registeredToken: String? = nil
            for _ in 0..<10 {
                if Task.isCancelled { return }
                if let token = activityManager.pushTokenHex {
                    await registerResumedWorkout(
                        pushToken: token,
                        fromIndex: fromIndex,
                        adjustedFirstDuration: pausedSecondsRemaining,
                        startTime: startTime
                    )
                    registeredToken = token
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }

            guard registeredToken != nil else {
                print("Push token unavailable after resume — no server pushes will fire")
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                if let token = activityManager.pushTokenHex, token != registeredToken {
                    await updateTokenWithServer(pushToken: token)
                    registeredToken = token
                }
            }
        }
    }

    private func registerResumedWorkout(
        pushToken: String,
        fromIndex: Int,
        adjustedFirstDuration: Int,
        startTime: TimeInterval
    ) async {
        let remaining = intervals[fromIndex...]
        let intervalData: [[String: Any]] = remaining.enumerated().map { i, interval in
            var dict: [String: Any] = [
                "label": interval.baseLabel,
                "duration": i == 0 ? adjustedFirstDuration : interval.duration,
            ]
            if let raw = interval.zoneRawValue {
                dict["zoneRawValue"] = raw
            }
            return dict
        }

        let body: [String: Any] = [
            "pushToken": pushToken,
            "intervals": intervalData,
            "totalIntervals": intervals.count,
            "workoutName": workoutName,
            "startTime": startTime,
            "startIndex": fromIndex,
        ]

        guard let url = URL(string: "\(Self.serverBaseURL)/workouts"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Self.apiSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let workoutId = json["workoutId"] as? String else {
                print("Server re-registration after pause failed")
                return
            }
            self.serverWorkoutId = workoutId
            print("Re-registered workout after pause: \(workoutId) (from interval \(fromIndex))")
        } catch {
            print("Failed to re-register after pause: \(error)")
        }
    }

    private func pollForPushTokenAndRegister() {
        print("Server URL: \(Self.serverBaseURL)")
        pushTokenPollTask?.cancel()
        pushTokenPollTask = Task { @MainActor in
            // Initial registration: poll until token is available (up to 30s)
            var registeredToken: String? = nil
            for _ in 0..<30 {
                if Task.isCancelled { return }
                if let token = activityManager.pushTokenHex {
                    await registerWithServer(pushToken: token)
                    registeredToken = token
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }

            guard registeredToken != nil else {
                print("Push token not received within timeout")
                return
            }

            // Token rotation: continue checking every 30s for a new token
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                if let token = activityManager.pushTokenHex, token != registeredToken {
                    await updateTokenWithServer(pushToken: token)
                    registeredToken = token
                }
            }
        }
    }

    private func registerWithServer(pushToken: String) async {
        guard let startDate = workoutStartDate else { return }

        let intervalData: [[String: Any]] = intervals.map { interval in
            var dict: [String: Any] = [
                "label": interval.baseLabel,
                "duration": interval.duration,
            ]
            if let raw = interval.zoneRawValue {
                dict["zoneRawValue"] = raw
            }
            return dict
        }

        let body: [String: Any] = [
            "pushToken": pushToken,
            "intervals": intervalData,
            "totalIntervals": intervals.count,
            "workoutName": workoutName,
            "startTime": startDate.timeIntervalSince1970,
        ]

        guard let url = URL(string: "\(Self.serverBaseURL)/workouts"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Self.apiSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let workoutId = json["workoutId"] as? String else {
                print("Server registration failed")
                return
            }
            self.serverWorkoutId = workoutId
            print("Registered workout with server: \(workoutId)")
        } catch {
            print("Failed to register with server: \(error)")
        }
    }

    private func updateTokenWithServer(pushToken: String) async {
        guard let workoutId = serverWorkoutId else { return }

        let body: [String: Any] = ["pushToken": pushToken]
        guard let url = URL(string: "\(Self.serverBaseURL)/workouts/\(workoutId)/token"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Self.apiSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Updated push token on server for workout: \(workoutId)")
            }
        } catch {
            print("Failed to update token on server: \(error)")
        }
    }

    private func cancelServerWorkout() {
        guard let workoutId = serverWorkoutId else { return }
        serverWorkoutId = nil

        guard let url = URL(string: "\(Self.serverBaseURL)/workouts/\(workoutId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(Self.apiSecret)", forHTTPHeaderField: "Authorization")

        Task.detached {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("Cancelled server workout: \(workoutId)")
                }
            } catch {
                print("Failed to cancel server workout: \(error)")
            }
        }
    }
}
