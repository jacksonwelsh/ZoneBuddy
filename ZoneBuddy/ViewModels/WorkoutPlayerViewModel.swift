import SwiftUI
import SwiftData
#if os(iOS)
import FTMSKit
#endif
import HealthKit

struct WorkoutSummary {
    let avgPower: Int
    let maxPower: Int
    let totalDistance: Double // in meters
    let totalCalories: Int
    let totalOutputKJ: Double
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let duration: Int
    let zoneTimeBreakdown: [PowerZone: Int] // zone -> seconds spent

    private static var usesMetric: Bool {
        Locale.current.measurementSystem != .us
    }

    var formattedDistance: String {
        if Self.usesMetric {
            return String(format: "%.1f", totalDistance / 1000.0)
        } else {
            return String(format: "%.1f", totalDistance / 1609.344)
        }
    }

    var distanceUnit: String {
        Self.usesMetric ? "km" : "mi"
    }
}

@Observable
final class WorkoutPlayerViewModel {
    // MARK: - State

    private(set) var currentIntervalIndex: Int = 0
    private(set) var secondsRemaining: Int = 0
    private(set) var totalElapsedSeconds: Int = 0
    private(set) var isRunning: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var showTransitionBanner: Bool = false
    private(set) var workoutSummary: WorkoutSummary?
    private(set) var savedSession: WorkoutSession?
    /// Average power held during the FTP test interval, computed at workout end.
    /// Nil when not in FTP test mode or when no power samples were captured.
    private(set) var ftpTestAvgPower: Int?

    var computedFTPFromTest: Int? {
        guard let avg = ftpTestAvgPower else { return nil }
        return FTPTestProtocol.computeFTP(avgPower: avg)
    }

    var isFTPTest: Bool { ftpTestIntervalIndex != nil }
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

    var isPaused: Bool {
        !isRunning && workoutHasStarted && !isFinished
    }

    // MARK: - FTP & Power Zone Computed Properties

    var currentFTP: Int {
        SettingsManager.shared.functionalThresholdPower
    }

    var targetPowerRange: ClosedRange<Int>? {
        guard let zone = currentInterval?.zone else { return nil }
        return zone.wattRange(ftp: currentFTP)
    }

    var targetRangeDescription: String? {
        guard let zone = currentInterval?.zone else { return nil }
        return zone.rangeDescription(ftp: currentFTP)
    }

    var powerAsPercentOfFTP: Int? {
        guard let power = currentBikeData?.instantaneousPower, currentFTP > 0 else { return nil }
        return Int((Double(power) / Double(currentFTP)) * 100)
    }

    var actualPowerZone: PowerZone? {
        guard let power = currentBikeData?.instantaneousPower else { return nil }
        return PowerZone.zone(forPower: power, ftp: currentFTP)
    }

    var isConnectedToBike: Bool {
        bikeManager?.isConnected ?? false
    }

    var currentBikeData: BikeData? {
        bikeManager?.latestBikeData
    }

    var currentAvgPower: Int? {
        let powers = allBikeSamples.compactMap(\.power)
        guard !powers.isEmpty else { return nil }
        return powers.reduce(0, +) / powers.count
    }

    var currentTotalCalories: Int? {
        // Prefer Watch's native calorie calculation when available
        if let live = healthKitManager?.liveCalories {
            return Int(live)
        }
        // Always compute from integrated power output — bike-reported calories are unreliable
        guard let outputKJ = currentTotalOutputKJ else { return nil }
        let cyclingEfficiency = 0.25
        return Int(outputKJ * 1000.0 / (cyclingEfficiency * 4184.0))
    }

    var currentTotalOutputKJ: Double? {
        guard allBikeSamples.count > 1 else { return nil }
        var joules: Double = 0
        for i in 1..<allBikeSamples.count {
            if let power = allBikeSamples[i].power {
                let dt = allBikeSamples[i].timestamp.timeIntervalSince(allBikeSamples[i - 1].timestamp)
                if dt > 0 && dt < 30 {
                    joules += Double(power) * dt
                }
            }
        }
        return joules / 1000.0
    }

    /// Heart rate: prefer Watch/HK streamer, fall back to bike HR only when streamer has no data.
    /// Bike HR of 0 means no sensor paired — treat as nil.
    var currentHeartRate: Int? {
        if let hkHR = heartRateStreamer?.latestHeartRate {
            return hkHR
        }
        if let bikeHR = currentBikeData?.heartRate, bikeHR > 0 {
            return bikeHR
        }
        return nil
    }

    var currentMaxHR: Int {
        SettingsManager.shared.maxHeartRate
    }

    /// Running average heart rate across the current workout session.
    var averageHeartRate: Int? {
        if !allHRSamples.isEmpty {
            return allHRSamples.reduce(0, +) / allHRSamples.count
        }
        let bikeBPMs = allBikeSamples.compactMap(\.heartRate).filter { $0 > 0 }
        if !bikeBPMs.isEmpty {
            return bikeBPMs.reduce(0, +) / bikeBPMs.count
        }
        return nil
    }

    /// Distance computed by integrating speed samples over time (meters).
    var currentTotalDistance: Double {
        computedDistanceMeters
    }

    // MARK: - Private

    let intervals: [Interval]
    private let timerProvider: TimerProviding
    private let speechCueProvider: SpeechCueProviding?
    let musicPlaybackManager: MusicPlaybackManaging?
    let workoutName: String
    let templateID: UUID?
    let transitionWarningDuration: Int
    private let spokenDurationSecondsThreshold: Int = 90
    private let dateProvider: @Sendable () -> Date
    private let playlistID: String?
    private let playlistKind: String?
    private let playlistShuffle: Bool
    private let playlistRepeat: Bool
    private let playlistAutoMix: Bool

    let bikeManager: BikeConnecting?
    private let healthKitManager: HealthKitWorkoutRecording?
    private let heartRateStreamer: HeartRateStreaming?
    let ftpTestIntervalIndex: Int?
    private let shouldPersistSession: Bool
    private var ftpTestStartedAt: Date?
    private var ftpTestEndedAt: Date?
    private var healthKitFlushTask: Task<Void, Never>?
    private var allBikeSamples: [BikeDataSample] = []
    private var watchHRBuffer: [(bpm: Int, date: Date)] = []
    private var allHRSamples: [Int] = []
    private var lastBufferedHR: Int?
    private var zoneTimeAccumulator: [PowerZone: Int] = [:]
    private(set) var onTargetZoneAccumulator: [PowerZone: Int] = [:]
    private(set) var hrZoneTimeAccumulator: [HeartRateZone: Int] = [:]
    private var lastZoneTickIndex: Int = -1
    /// Running distance in meters, computed by integrating speed over time from bike samples.
    private(set) var computedDistanceMeters: Double = 0
    private var lastSpeedSampleDate: Date?

    private var timerTask: Task<Void, Never>?
    private var workoutStartDate: Date?
    private var totalSecondsAccumulatedBeforePause: TimeInterval = 0
    private var workoutHasStarted: Bool = false

    // MARK: - Init

    init(
        intervals: [Interval],
        timerProvider: TimerProviding,
        speechCueProvider: SpeechCueProviding? = nil,
        workoutName: String = "",
        templateID: UUID? = nil,
        transitionWarningDuration: Int = 10,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        musicPlaybackManager: MusicPlaybackManaging? = nil,
        playlistID: String? = nil,
        playlistKind: String? = nil,
        playlistShuffle: Bool = false,
        playlistRepeat: Bool = false,
        playlistAutoMix: Bool = false,
        bikeManager: BikeConnecting? = nil,
        healthKitManager: HealthKitWorkoutRecording? = nil,
        heartRateStreamer: HeartRateStreaming? = nil,
        ftpTestIntervalIndex: Int? = nil,
        shouldPersistSession: Bool = true
    ) {
        self.intervals = intervals
        self.timerProvider = timerProvider
        self.speechCueProvider = speechCueProvider
        self.musicPlaybackManager = musicPlaybackManager
        self.workoutName = workoutName
        self.templateID = templateID
        self.transitionWarningDuration = transitionWarningDuration
        self.dateProvider = dateProvider
        self.playlistID = playlistID
        self.playlistKind = playlistKind
        self.playlistShuffle = playlistShuffle
        self.playlistRepeat = playlistRepeat
        self.playlistAutoMix = playlistAutoMix
        self.bikeManager = bikeManager
        self.healthKitManager = healthKitManager
        self.heartRateStreamer = heartRateStreamer
        self.ftpTestIntervalIndex = ftpTestIntervalIndex
        self.shouldPersistSession = shouldPersistSession
        if let first = intervals.first {
            self.secondsRemaining = first.duration
        }
    }

    deinit {
        timerTask?.cancel()
        healthKitFlushTask?.cancel()
        speechCueProvider?.stop()
        heartRateStreamer?.stopMonitoring()
    }

    // MARK: - Actions

    func start(atElapsedSeconds elapsed: Int = 0) {
        guard !isRunning && !isFinished && !intervals.isEmpty else { return }

        if elapsed > 0 && !workoutHasStarted {
            totalSecondsAccumulatedBeforePause = TimeInterval(elapsed)
            recalculateIntervalState(totalElapsed: TimeInterval(elapsed))
            totalElapsedSeconds = elapsed
            if isFinished { return }
        }

        workoutStartDate = dateProvider()
        isRunning = true

        if !workoutHasStarted {
            workoutHasStarted = true
            startMusicPlayback()
            speakCurrentLabel(delay: musicPlaybackManager != nil)
            startHealthKitAndHeartRate()
        } else {
            // Discard any bike samples that accumulated during the pause,
            // then restart the HealthKit flush loop from a clean baseline.
            #if !os(watchOS)
            _ = bikeManager?.drainSamples()
            lastSpeedSampleDate = nil
            if healthKitManager != nil {
                startHealthKitFlushLoop()
            }
            #endif
            healthKitManager?.resumeWorkout()
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
                    stopWorkout()
                    self.finishHealthKitWorkout()
                    break
                }

                // Track time spent in each zone (1 second per tick)
                let targetZone = self.currentInterval?.zone
                if let zone = targetZone {
                    self.zoneTimeAccumulator[zone, default: 0] += 1
                }

                // On-target adherence: actual power zone matches prescribed target
                if let target = targetZone,
                   let actual = self.actualPowerZone,
                   actual == target {
                    self.onTargetZoneAccumulator[target, default: 0] += 1
                }

                // Heart rate zone time (actual)
                let maxHR = SettingsManager.shared.maxHeartRate
                if let bpm = self.currentHeartRate, maxHR > 0,
                   let hrZone = HeartRateZone.zone(forBPM: bpm, maxHR: maxHR) {
                    self.hrZoneTimeAccumulator[hrZone, default: 0] += 1
                }

                // Collect HR samples for summary on all platforms; buffer for HealthKit write on iOS only.
                if let hr = self.heartRateStreamer?.latestHeartRate {
                    self.allHRSamples.append(hr)
                    #if os(iOS)
                    if hr != self.lastBufferedHR {
                        self.watchHRBuffer.append((bpm: hr, date: self.dateProvider()))
                        self.lastBufferedHR = hr
                    }
                    #endif
                }

                if self.currentIntervalIndex != previousIndex {
                    self.speakCurrentLabel()
                    self.handleFTPTestIntervalTransition(from: previousIndex, to: self.currentIntervalIndex)
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

        // Flush any remaining bike/HR samples from this segment so they are
        // counted in running averages and the HealthKit record before the pause.
        healthKitFlushTask?.cancel()
        healthKitFlushTask = nil
        #if !os(watchOS)
        flushBikeSamplesToHealthKit()
        lastSpeedSampleDate = nil
        #endif
        healthKitManager?.pauseWorkout()

        musicPlaybackManager?.pausePlayback()
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
        speechCueProvider?.stop()
        musicPlaybackManager?.stopPlayback()
        heartRateStreamer?.stopMonitoring()
    }

    func startBackgroundKeepAlive() {
        speechCueProvider?.startBackgroundKeepAlive()
    }

    func stopBackgroundKeepAlive() {
        speechCueProvider?.stopBackgroundKeepAlive()
    }

    func recalculateOnForeground() {
        guard isRunning, let startDate = workoutStartDate else { return }
        let segmentElapsed = dateProvider().timeIntervalSince(startDate)
        let totalElapsed = segmentElapsed + totalSecondsAccumulatedBeforePause
        totalElapsedSeconds = Int(totalElapsed)
        recalculateIntervalState(totalElapsed: totalElapsed)
    }

    func endWorkout() {
        guard workoutHasStarted else { return }
        workoutHasStarted = false
        stopWorkout()
        finishHealthKitWorkout()
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

    private func speakCurrentLabel(delay: Bool = false) {
        guard audioCuesEnabled else { return }
        guard let interval = currentInterval else { return }
        let spokenLabel: String
        if ftpTestIntervalIndex != nil {
            spokenLabel = FTPTestProtocol.phaseLabel(forIndex: currentIntervalIndex)
        } else if isLastInterval && interval.zone == .zone1 {
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
                speechCueProvider?.speak(text)
            }
        } else {
            speechCueProvider?.speak(text)
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

    // MARK: - HealthKit Integration

    /// Single entry point for all HealthKit work: requests authorization once,
    /// then starts both the workout recording and HR streaming sequentially.
    private func startHealthKitAndHeartRate() {
        let startDate = workoutStartDate ?? dateProvider()

        #if os(watchOS)
        // Always start HKWorkoutSession on Watch — this is the keep-alive mechanism.
        Task {
            if let healthKitManager {
                let authorized = await healthKitManager.requestAuthorization()
                if authorized {
                    _ = await healthKitManager.startWorkout(startDate: startDate)
                }
            }
            heartRateStreamer?.startMonitoring(from: startDate)
        }
        #else
        let hasBike = bikeManager?.isConnected == true

        if hasBike, let mgr = bikeManager as? LiveBikeConnectionManager {
            mgr.clearSamples()
        }
        if hasBike {
            allBikeSamples = []
        }
        allHRSamples = []
        watchHRBuffer = []
        lastBufferedHR = nil

        // Always start HR streaming immediately — BLE-based streamers (iPad)
        // don't need HealthKit and must not wait for authorization.
        heartRateStreamer?.startMonitoring(from: startDate)

        guard HKHealthStore.isHealthDataAvailable() else { return }

        Task {
            if let healthKitManager {
                let authorized = await healthKitManager.requestAuthorization()
                if authorized {
                    let started = await healthKitManager.startWorkout(startDate: startDate)
                    if started {
                        startHealthKitFlushLoop()
                    }
                }
            }
        }
        #endif
    }

    private func startHealthKitFlushLoop() {
        healthKitFlushTask?.cancel()
        healthKitFlushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                flushBikeSamplesToHealthKit()
            }
        }
    }

    private func flushBikeSamplesToHealthKit() {
        guard let healthKitManager else { return }

        // Drain bike samples if available
        var bikeSamples: [BikeDataSample] = []
        if let bikeManager {
            bikeSamples = bikeManager.drainSamples()
            if !bikeSamples.isEmpty {
                integrateSpeedSamples(bikeSamples)
                allBikeSamples.append(contentsOf: bikeSamples)
            }
        }

        // Drain Watch HR buffer
        let hrSamples = watchHRBuffer
        watchHRBuffer.removeAll()

        // If we have Watch HR, strip bike HR to avoid duplicates within the same workout
        let hasWatchHR = !hrSamples.isEmpty
        let filteredBikeSamples: [BikeDataSample]
        if hasWatchHR {
            filteredBikeSamples = bikeSamples.map { sample in
                BikeDataSample(
                    timestamp: sample.timestamp,
                    power: sample.power,
                    cadence: sample.cadence,
                    heartRate: nil,
                    speed: sample.speed,
                    distance: sample.distance,
                    calories: sample.calories
                )
            }
        } else {
            filteredBikeSamples = bikeSamples
        }

        Task {
            if !filteredBikeSamples.isEmpty {
                await healthKitManager.addSamples(filteredBikeSamples)
            }
            if !hrSamples.isEmpty {
                await healthKitManager.addHeartRateSamples(hrSamples)
            }
        }
    }

    /// Integrate speed (km/h) over time intervals between consecutive samples to accumulate distance in meters.
    private func integrateSpeedSamples(_ samples: [BikeDataSample]) {
        for sample in samples {
            if let speed = sample.speed, let lastDate = lastSpeedSampleDate {
                let dt = sample.timestamp.timeIntervalSince(lastDate)
                if dt > 0 && dt < 30 { // ignore gaps > 30s (e.g. pauses)
                    // speed is km/h, convert to m/s: * 1000/3600
                    let metersPerSecond = speed * 1000.0 / 3600.0
                    computedDistanceMeters += metersPerSecond * dt
                }
            }
            lastSpeedSampleDate = sample.timestamp
        }
    }

    private func handleFTPTestIntervalTransition(from previousIndex: Int, to newIndex: Int) {
        guard let testIndex = ftpTestIntervalIndex else { return }
        let now = dateProvider()
        if newIndex == testIndex && ftpTestStartedAt == nil {
            ftpTestStartedAt = now
        }
        if previousIndex == testIndex && ftpTestEndedAt == nil {
            ftpTestEndedAt = now
        }
    }

    /// Computes the average power held during the FTP test interval from `allBikeSamples`,
    /// filtered to power values > 0 within the test interval's time window. Called from
    /// `finishHealthKitWorkout()` after the final sample drain.
    private func finalizeFTPTestAvgPower() {
        guard ftpTestIntervalIndex != nil, let start = ftpTestStartedAt else { return }
        let end = ftpTestEndedAt ?? dateProvider()
        let testPowers = allBikeSamples
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .compactMap(\.power)
            .filter { $0 > 0 }
        guard !testPowers.isEmpty else { return }
        ftpTestAvgPower = testPowers.reduce(0, +) / testPowers.count
    }

    private func finishHealthKitWorkout() {
        healthKitFlushTask?.cancel()
        healthKitFlushTask = nil

        #if os(watchOS)
        if let healthKitManager {
            let endDate = dateProvider()
            Task {
                await healthKitManager.endWorkout(endDate: endDate, metadata: [:])
            }
        }

        if shouldPersistSession {
            let summaryAvgHR = allHRSamples.isEmpty ? nil : allHRSamples.reduce(0, +) / allHRSamples.count
            let summaryMaxHR = allHRSamples.max()
            persistWorkoutSession(
                avgPower: 0,
                maxPower: 0,
                totalOutputKJ: 0,
                computedCalories: 0,
                avgHeartRate: summaryAvgHR,
                maxHeartRate: summaryMaxHR
            )
        }
        #else
        guard let healthKitManager else { return }

        // Drain any remaining bike samples
        var remaining: [BikeDataSample] = []
        if let bikeManager {
            remaining = bikeManager.drainSamples()
            allBikeSamples.append(contentsOf: remaining)
            integrateSpeedSamples(remaining)
        }

        finalizeFTPTestAvgPower()

        // Drain remaining Watch HR buffer (still needed for HealthKit sample writing)
        let finalHRSamples = watchHRBuffer
        watchHRBuffer.removeAll()

        // Compute summary
        let powers = allBikeSamples.compactMap(\.power)
        // Use the per-tick running HR list (never drained) for summary.
        // Bike HR fallback filters out 0 (means no HR sensor paired with bike).
        let bikeHeartRates = allBikeSamples.compactMap(\.heartRate).filter { $0 > 0 }
        let heartRates = allHRSamples.isEmpty ? bikeHeartRates : allHRSamples

        // Compute total output (kJ) from power samples: Σ(watts × dt) / 1000
        var totalJoules: Double = 0
        if allBikeSamples.count > 1 {
            for i in 1..<allBikeSamples.count {
                if let power = allBikeSamples[i].power {
                    let dt = allBikeSamples[i].timestamp.timeIntervalSince(allBikeSamples[i - 1].timestamp)
                    if dt > 0 && dt < 30 {
                        totalJoules += Double(power) * dt
                    }
                }
            }
        }
        let totalOutputKJ = totalJoules / 1000.0
        let cyclingEfficiency = 0.25
        let computedCalories = Int(totalJoules / (cyclingEfficiency * 4184.0))

        let summaryAvgPower = powers.isEmpty ? 0 : powers.reduce(0, +) / powers.count
        let summaryMaxPower = powers.max() ?? 0
        let summaryAvgHR = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count
        let summaryMaxHR = heartRates.max()

        workoutSummary = WorkoutSummary(
            avgPower: summaryAvgPower,
            maxPower: summaryMaxPower,
            totalDistance: computedDistanceMeters,
            totalCalories: computedCalories,
            totalOutputKJ: totalOutputKJ,
            avgHeartRate: summaryAvgHR,
            maxHeartRate: summaryMaxHR,
            duration: totalElapsedSeconds,
            zoneTimeBreakdown: zoneTimeAccumulator
        )

        if shouldPersistSession {
            persistWorkoutSession(
                avgPower: summaryAvgPower,
                maxPower: summaryMaxPower,
                totalOutputKJ: totalOutputKJ,
                computedCalories: computedCalories,
                avgHeartRate: summaryAvgHR,
                maxHeartRate: summaryMaxHR
            )
        }

        let endDate = dateProvider()
        var metadata: [String: Any] = [:]
        if totalOutputKJ > 0 {
            metadata["TotalOutputKJ"] = totalOutputKJ
        }

        // Strip bike HR from remaining samples if we have Watch HR
        let hasWatchHR = !finalHRSamples.isEmpty
        let filteredRemaining: [BikeDataSample]
        if hasWatchHR && !remaining.isEmpty {
            filteredRemaining = remaining.map { sample in
                BikeDataSample(
                    timestamp: sample.timestamp,
                    power: sample.power,
                    cadence: sample.cadence,
                    heartRate: nil,
                    speed: sample.speed,
                    distance: sample.distance,
                    calories: sample.calories
                )
            }
        } else {
            filteredRemaining = remaining
        }

        Task {
            if !filteredRemaining.isEmpty {
                await healthKitManager.addSamples(filteredRemaining)
            }
            if !finalHRSamples.isEmpty {
                await healthKitManager.addHeartRateSamples(finalHRSamples)
            }
            await healthKitManager.endWorkout(endDate: endDate, metadata: metadata)
        }
        #endif
    }

    private func persistWorkoutSession(
        avgPower: Int,
        maxPower: Int,
        totalOutputKJ: Double,
        computedCalories: Int,
        avgHeartRate: Int?,
        maxHeartRate: Int?
    ) {
        let session = WorkoutSession(
            templateID: templateID,
            name: workoutName,
            transitionWarningDuration: transitionWarningDuration,
            completedAt: dateProvider(),
            totalDuration: totalElapsedSeconds,
            avgPower: avgPower > 0 ? avgPower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            totalOutputKJ: totalOutputKJ > 0 ? totalOutputKJ : nil,
            totalDistance: computedDistanceMeters > 0 ? computedDistanceMeters : nil,
            totalCalories: computedCalories > 0 ? computedCalories : nil,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            onTargetZoneSeconds: onTargetZoneAccumulator,
            scheduledZoneSeconds: zoneTimeAccumulator,
            hrZoneSeconds: hrZoneTimeAccumulator,
            ftpAtTime: SettingsManager.shared.functionalThresholdPower,
            maxHRAtTime: SettingsManager.shared.maxHeartRate,
            bikeWasConnected: isConnectedToBike
        )

        let snapshots = intervals.enumerated().map { index, interval in
            SessionInterval(
                zone: interval.zone,
                duration: interval.duration,
                sortOrder: index
            )
        }
        session.intervals = snapshots

        let context = DataStore.shared.context
        context.insert(session)
        for snapshot in snapshots {
            context.insert(snapshot)
        }
        do {
            try context.save()
            self.savedSession = session
        } catch {
            print("Failed to save WorkoutSession: \(error)")
        }
    }
}
