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

    var formattedDistance: String { UnitFormatting.distance(meters: totalDistance) }
    var distanceUnit: String { UnitFormatting.distanceUnit }
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
    /// Nil when not running a 20-min FTP test or when no power samples were captured.
    private(set) var ftpTestAvgPower: Int?
    /// Best 1-minute rolling average power observed during the ramp test window.
    /// Nil when not running a ramp test or when fewer than 60 samples were captured.
    private(set) var ftpTestBestMinutePower: Int?

    var computedFTPFromTest: Int? {
        guard let kind = ftpTestKind else { return nil }
        switch kind {
        case .twentyMinute:
            guard let avg = ftpTestAvgPower else { return nil }
            return FTPTestProtocol.computeFTP(avgPower: avg)
        case .ramp:
            guard let best = ftpTestBestMinutePower else { return nil }
            return Int((Double(best) * 0.75).rounded())
        }
    }

    var isFTPTest: Bool { ftpTestKind != nil }

    /// Explicit target watts to surface during a ramp test step (e.g. "220 W").
    /// Nil for the 20-min test (no target) and outside FTP-test workouts.
    var rampStepTargetWatts: Int? {
        guard ftpTestKind == .ramp else { return nil }
        return currentInterval?.targetWatts
    }
    var showTimer: Bool = true
    var audioCuesEnabled: Bool

    /// True once the workout has crossed into its first non-warmup interval AND
    /// the connected trainer supports power-target setting. When true the
    /// player offers an ERG toggle; ERG state itself lives on `trainerController`.
    private(set) var ergAvailable: Bool = false

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
        settings.functionalThresholdPower
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

    #if os(iOS)
    var trainerController: (any TrainerControlling)? {
        bikeManager?.trainerController
    }

    /// Target watts to drive the trainer to for the current interval. When the
    /// interval carries an explicit `targetWatts` (ramp test steps), that wins.
    /// Otherwise the band midpoint of the interval's zone. Nil for warmup
    /// intervals with no explicit target.
    var ergTargetWattsForCurrentInterval: Int? {
        if let explicit = currentInterval?.targetWatts { return explicit }
        guard let zone = currentInterval?.zone else { return nil }
        let range = zone.wattRange(ftp: currentFTP)
        let midpoint = (range.lowerBound + range.upperBound) / 2
        return midpoint
    }
    #endif

    var currentAvgPower: Int? {
        let powers = allBikeSamples.compactMap(\.power)
        guard !powers.isEmpty else { return nil }
        return powers.reduce(0, +) / powers.count
    }

    var currentTotalCalories: Int? {
        let powerBased = WorkoutSampleAggregator.estimatedCalories(in: allBikeSamples)
        #if os(iOS)
        // Mirror the finalization policy: HealthKit and the persisted session both
        // get `max(power_based, watch_HR)`, so the in-workout display tracks the
        // same value the history row and Fitness will show afterwards.
        if let watchKcal = BLEHeartRateScanner.shared.latestWatchEnergyKcal,
           watchKcal > (powerBased ?? 0) {
            return watchKcal
        }
        #else
        // On watchOS the live builder exposes its own running estimate.
        if let live = healthKitManager?.liveCalories {
            return Int(live)
        }
        #endif
        return powerBased
    }

    var currentTotalOutputKJ: Double? {
        WorkoutSampleAggregator.totalOutputKJ(in: allBikeSamples)
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
        settings.maxHeartRate
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
    let mode: WorkoutMode
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
    let ftpTestKind: FTPTestKind?
    private let shouldPersistSession: Bool
    private let settings: any SettingsReading
    private let sessionPersister: WorkoutSessionPersisting?
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
    /// Running distance in meters, computed by integrating speed over time from bike samples.
    private(set) var computedDistanceMeters: Double = 0
    private var lastSpeedSampleDate: Date?

    private var timerTask: Task<Void, Never>?
    private var workoutStartDate: Date?
    private var totalSecondsAccumulatedBeforePause: TimeInterval = 0
    private var workoutHasStarted: Bool = false

    /// Consecutive seconds the rider has held cadence below the ramp-test
    /// failure threshold. Used to auto-end the ramp test when the rider can't
    /// turn the cranks fast enough to hold the ERG target.
    private var lowCadenceTickCount: Int = 0
    /// Cadence (rpm) below which we consider the rider to have failed the
    /// current ramp step. 50 rpm matches Zwift / TrainerRoad's heuristic.
    private static let rampFailureCadenceThreshold: Double = 50
    /// Consecutive 1Hz ticks below the threshold required before we call it.
    private static let rampFailureTickCount: Int = 3
    /// Grace period at the start of each ramp step. ERG snapping the target
    /// up can briefly drop cadence; don't end the test on that transient.
    private static let rampStepGraceSeconds: Int = 5

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
        ftpTestKind: FTPTestKind? = nil,
        shouldPersistSession: Bool = true,
        settings: any SettingsReading = SettingsManager.shared,
        sessionPersister: WorkoutSessionPersisting? = nil,
        mode: WorkoutMode = .scheduled
    ) {
        self.intervals = intervals
        self.mode = mode
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
        self.ftpTestKind = ftpTestKind
        self.shouldPersistSession = shouldPersistSession
        self.settings = settings
        self.sessionPersister = sessionPersister
        self.audioCuesEnabled = settings.audioCuesEnabled
        if case .freeRide(let goal) = mode, case .time(let s) = goal {
            self.secondsRemaining = s
        } else if let first = intervals.first {
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
        guard !isRunning && !isFinished && (!intervals.isEmpty || mode.isFreeRide) else { return }

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
            if !mode.isFreeRide {
                speakCurrentLabel(delay: musicPlaybackManager != nil)
            }
            startHealthKitAndHeartRate()
            #if os(iOS)
            applyERGForCurrentInterval()
            #endif
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
                    // Route through endWorkout() so workoutHasStarted is cleared. Otherwise
                    // the user's Done-tap re-enters endWorkout() and we persist + finalize twice
                    // (duplicate history row, mismatched HealthKit totals).
                    self.endWorkout()
                    break
                }

                // Track time spent in each zone (1 second per tick). In Free Ride
                // there is no prescribed zone, so accumulate based on the actual
                // power zone — the completion screen reuses scheduledZoneSeconds
                // to render time-in-zone for the ride.
                if self.mode.isFreeRide {
                    if let actual = self.actualPowerZone {
                        self.zoneTimeAccumulator[actual, default: 0] += 1
                    }
                } else {
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
                }

                // Heart rate zone time (actual)
                let maxHR = self.settings.maxHeartRate
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

                if !self.mode.isFreeRide, self.currentIntervalIndex != previousIndex {
                    self.speakCurrentLabel()
                    self.handleFTPTestIntervalTransition(from: previousIndex, to: self.currentIntervalIndex)
                    #if os(iOS)
                    let prevWasWarmup = previousIndex >= 0
                        && previousIndex < self.intervals.count
                        && self.intervals[previousIndex].isWarmup
                    self.applyERGForCurrentInterval(previousIntervalWasWarmup: prevWasWarmup)
                    #endif
                    self.lowCadenceTickCount = 0
                }

                #if os(iOS)
                if self.ftpTestKind == .ramp {
                    self.checkRampTestFailure()
                    if self.isFinished { break }
                }
                #endif
            }
        }
    }

    #if os(iOS)
    /// Watches cadence during ramp steps and skips the rider into the cooldown
    /// when they can no longer turn the cranks fast enough to make the trainer
    /// hold the ERG target. Cadence collapse is the conventional "failure"
    /// signal (Zwift / TrainerRoad both detect failure this way) — once the
    /// rider blows up, additional ramp samples wouldn't add useful data, so we
    /// freeze the FTP window and drop them into the 5-minute easy spin.
    private func checkRampTestFailure() {
        guard let interval = currentInterval,
              interval.targetWatts != nil,
              let controller = trainerController,
              controller.mode == .erg else {
            lowCadenceTickCount = 0
            return
        }

        // Brief grace window so the cadence dip from ERG snapping to a new
        // target doesn't get counted as failure.
        let elapsedInInterval = interval.duration - secondsRemaining
        if elapsedInInterval < Self.rampStepGraceSeconds {
            lowCadenceTickCount = 0
            return
        }

        guard let cadence = currentBikeData?.instantaneousCadence else {
            lowCadenceTickCount = 0
            return
        }

        if cadence < Self.rampFailureCadenceThreshold {
            lowCadenceTickCount += 1
            if lowCadenceTickCount >= Self.rampFailureTickCount {
                jumpToCooldownAfterRampFailure()
            }
        } else {
            lowCadenceTickCount = 0
        }
    }

    /// Skip the remaining ramp steps and drop the rider into the cooldown
    /// interval (the last interval in the ramp protocol). Closes the FTP
    /// sampling window at the moment of failure and releases ERG so the rider
    /// can spin easy — `applyERGForCurrentInterval` is a no-op on cooldown
    /// (no zone, no target), so the trainer would otherwise stay locked at
    /// the wattage they just failed.
    private func jumpToCooldownAfterRampFailure() {
        let previousIndex = currentIntervalIndex
        let cooldownIndex = intervals.count - 1
        guard cooldownIndex > previousIndex,
              cooldownIndex >= 0,
              intervals[cooldownIndex].targetWatts == nil else {
            // No cooldown interval to skip into — fall back to ending the
            // workout so we don't strand the user mid-ramp.
            isFinished = true
            isRunning = false
            endWorkout()
            return
        }

        let cooldownStartSeconds = intervals.prefix(cooldownIndex)
            .reduce(0) { $0 + TimeInterval($1.duration) }

        totalSecondsAccumulatedBeforePause = cooldownStartSeconds
        workoutStartDate = dateProvider()
        totalElapsedSeconds = Int(cooldownStartSeconds)
        recalculateIntervalState(totalElapsed: cooldownStartSeconds)
        lowCadenceTickCount = 0

        handleFTPTestIntervalTransition(from: previousIndex, to: currentIntervalIndex)
        speakCurrentLabel()

        if let controller = trainerController, controller.mode == .erg {
            Task { await controller.disableERG() }
        }
    }
    #endif

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

        #if os(iOS)
        if let controller = trainerController {
            Task { await controller.pause() }
        }
        #endif
    }

    func resume() {
        start()
        #if os(iOS)
        if let controller = trainerController {
            Task { await controller.resume() }
        }
        #endif
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

        #if os(iOS)
        if let controller = trainerController {
            Task { await controller.reset() }
        }
        #endif
    }

    // MARK: - ERG / Trainer Control

    #if os(iOS)
    /// Drives the trainer for the current interval. Warmups park the trainer in
    /// Level mode at level 0 so the rider can spin up at their own pace; active
    /// intervals snap to the zone-band midpoint (or explicit `targetWatts`) via
    /// ERG. Called on initial start and on every interval transition.
    ///
    /// `previousIntervalWasWarmup` tells us we just crossed from a warmup into
    /// the work portion of the ride. In that case we force ERG even if the
    /// trainer is currently in `.manualResistance` — the Level mode was set by
    /// us at the start of warmup, so the rider's level nudges don't count as
    /// "user opted out of ERG". Mid-workout Level switches (non-warmup origin)
    /// still block auto-ERG; the trainer-sheet mode picker is the path back.
    private func applyERGForCurrentInterval(previousIntervalWasWarmup: Bool = false) {
        guard let controller = trainerController,
              controller.capabilities?.powerTargetSettingSupported == true else {
            ergAvailable = false
            return
        }
        ergAvailable = true

        // 20-min FTP test: rider self-paces. ERG would lock target watts and
        // produce the cadence/resistance "spiral of death" the moment effort
        // wavers — release any ERG state held over from a prior workout.
        if ftpTestKind == .twentyMinute {
            if controller.mode == .erg {
                Task { await controller.disableERG() }
            }
            return
        }

        // Free Ride has no prescribed zone — never auto-apply. The manual
        // trainer sheet still works (ergAvailable stays true).
        if mode.isFreeRide { return }

        guard let interval = currentInterval else { return }

        // Explicit per-interval target (ramp test steps) drives the trainer
        // unconditionally — the protocol itself defines the workout, so it
        // beats both the warmup branch (ramp steps carry `zone: nil`) and any
        // user Level-mode opt-out.
        if let explicit = interval.targetWatts {
            Task { await controller.enableERG(targetWatts: explicit) }
            return
        }

        // Warmup: drop into Level mode at 0 so the rider can spin up freely.
        // If the trainer doesn't support resistance targets, release any held
        // ERG state instead — there's no zone to drive to during warmup.
        if interval.isWarmup {
            if controller.capabilities?.resistanceTargetSettingSupported == true {
                Task { await controller.setResistanceLevel(0) }
            } else if controller.mode == .erg {
                Task { await controller.disableERG() }
            }
            return
        }

        // User has explicitly chosen Level mode mid-workout — don't yank them
        // back into ERG at the next interval boundary. The carve-out for
        // `previousIntervalWasWarmup` covers the auto-applied warmup case.
        if controller.mode == .manualResistance && !previousIntervalWasWarmup { return }

        guard let target = ergTargetWattsForCurrentInterval else { return }
        if controller.ergUserOverridden { return }

        Task { await controller.enableERG(targetWatts: target) }
    }

    /// Re-enable ERG after a manual override. Called from the player's "Re-enable ERG"
    /// button. Clears the sticky flag and snaps the trainer back to the current zone midpoint.
    func reEnableERGForCurrentInterval() {
        guard let controller = trainerController,
              let target = ergTargetWattsForCurrentInterval else { return }
        Task { await controller.enableERG(targetWatts: target) }
    }

    /// Apply an absolute target watts written by the Watch via BLE. The Watch
    /// computes the new absolute target locally (baseline + Crown ticks) using
    /// the value the iPad publishes on `trainerTargetCharUUID`. We convert back
    /// to a delta from the iPad's current value and route through
    /// `adjustTargetWatts(by:)` to preserve its sticky-override semantics
    /// (stops interval boundaries from snapping away from the rider's nudge).
    func applyTrainerTarget(absoluteWatts: Int) {
        guard let controller = trainerController else { return }
        let delta = absoluteWatts - (controller.currentTargetWatts ?? 0)
        Task { await controller.adjustTargetWatts(by: delta) }
    }

    /// Apply an absolute resistance level written by the Watch via BLE. The Watch
    /// only writes here when the iPad has already published a non-nil resistance
    /// value (i.e. is in Level mode), so this never switches the active mode —
    /// it just sets the new level.
    func applyTrainerResistance(absoluteLevel: Int) {
        guard let controller = trainerController else { return }
        Task { await controller.setResistanceLevel(Double(absoluteLevel)) }
    }
    #endif

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
        switch ftpTestKind {
        case .twentyMinute:
            spokenLabel = FTPTestProtocol.phaseLabel(forIndex: currentIntervalIndex)
        case .ramp:
            spokenLabel = FTPRampTestProtocol.phaseLabel(forIndex: currentIntervalIndex)
        case .none:
            if isLastInterval && interval.zone == .zone1 {
                spokenLabel = "Cooldown"
            } else {
                spokenLabel = interval.spokenLabel
            }
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
        if case .freeRide(let goal) = mode {
            currentIntervalIndex = 0
            showTransitionBanner = false
            switch goal {
            case .time(let goalSeconds):
                let remaining = goalSeconds - Int(totalElapsed)
                secondsRemaining = max(0, remaining)
                if Int(totalElapsed) >= goalSeconds {
                    isFinished = true
                    isRunning = false
                    secondsRemaining = 0
                }
            case .distance(let goalMeters):
                secondsRemaining = 0
                if computedDistanceMeters >= goalMeters {
                    isFinished = true
                    isRunning = false
                }
            case .none:
                secondsRemaining = 0
            }
            return
        }

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
        // Cached cumulative watch-energy estimate is owned by a singleton and
        // would otherwise survive across workouts. If the Watch app doesn't
        // broadcast during this session (Watch off, BLE not reconnected, etc.)
        // we'd keep the previous workout's total — `max(power, stale_watch)`
        // then locks the displayed and HealthKit-published calorie count to
        // whatever the last session was. Reset so a missing Watch falls back
        // cleanly to the power-based number.
        BLEHeartRateScanner.shared.resetLatestWatchEnergyKcal()

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
        let (meters, last) = WorkoutSampleAggregator.integrateDistance(in: samples, startingFrom: lastSpeedSampleDate)
        computedDistanceMeters += meters
        lastSpeedSampleDate = last
    }

    private func handleFTPTestIntervalTransition(from previousIndex: Int, to newIndex: Int) {
        guard let range = sampleIntervalRange else { return }
        let now = dateProvider()
        let enteredRange = range.contains(newIndex) && !range.contains(previousIndex)
        let exitedRange = range.contains(previousIndex) && !range.contains(newIndex)
        if enteredRange && ftpTestStartedAt == nil {
            ftpTestStartedAt = now
        }
        if exitedRange && ftpTestEndedAt == nil {
            ftpTestEndedAt = now
        }
    }

    /// Interval indices whose bike samples count toward the FTP calculation,
    /// or nil when not running an FTP test. 20-min test = the test interval
    /// only. Ramp test = every ramp step (excludes warmup and cooldown).
    private var sampleIntervalRange: ClosedRange<Int>? {
        guard let kind = ftpTestKind else { return nil }
        switch kind {
        case .twentyMinute:
            return FTPTestProtocol.testIntervalIndex...FTPTestProtocol.testIntervalIndex
        case .ramp:
            return FTPRampTestProtocol.firstRampIntervalIndex...(FTPRampTestProtocol.cooldownIntervalIndex - 1)
        }
    }

    /// Computes the FTP-test result from samples captured inside the protocol's
    /// sampling window. 20-min test → average power across the window.
    /// Ramp test → best 1-minute rolling average across the ramp.
    /// Called from `finishHealthKitWorkout()` after the final sample drain.
    private func finalizeFTPTestResult() {
        guard let kind = ftpTestKind, let start = ftpTestStartedAt else { return }
        let end = ftpTestEndedAt ?? dateProvider()
        let testPowers = allBikeSamples
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .compactMap(\.power)
            .filter { $0 > 0 }
        guard !testPowers.isEmpty else { return }

        switch kind {
        case .twentyMinute:
            ftpTestAvgPower = testPowers.reduce(0, +) / testPowers.count
        case .ramp:
            ftpTestBestMinutePower = FTPRampTestProtocol.bestMinutePower(fromSamplePowers: testPowers)
        }
    }

    private func finishHealthKitWorkout() {
        healthKitFlushTask?.cancel()
        healthKitFlushTask = nil

        #if os(watchOS)
        if let healthKitManager {
            let endDate = dateProvider()
            Task {
                await healthKitManager.endWorkout(endDate: endDate, watchEnergyEstimateKcal: nil, metadata: [:])
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

        finalizeFTPTestResult()

        // Drain remaining Watch HR buffer (still needed for HealthKit sample writing)
        let finalHRSamples = watchHRBuffer
        watchHRBuffer.removeAll()

        // Compute summary
        let powers = allBikeSamples.compactMap(\.power)
        // Use the per-tick running HR list (never drained) for summary.
        // Bike HR fallback filters out 0 (means no HR sensor paired with bike).
        let bikeHeartRates = allBikeSamples.compactMap(\.heartRate).filter { $0 > 0 }
        let heartRates = allHRSamples.isEmpty ? bikeHeartRates : allHRSamples

        let totalOutputKJ = WorkoutSampleAggregator.totalOutputKJ(in: allBikeSamples) ?? 0
        let powerBasedCalories = WorkoutSampleAggregator.estimatedCalories(in: allBikeSamples) ?? 0

        // Mirror the HealthKit recorder's max(power, HR) policy so the in-app
        // history reflects the same calorie value we publish to Apple Health.
        let watchEnergyKcal: Double? = BLEHeartRateScanner.shared.latestWatchEnergyKcal.map(Double.init)
        let displayedCalories: Int
        if let watchKcal = watchEnergyKcal, Int(watchKcal) > powerBasedCalories {
            displayedCalories = Int(watchKcal)
        } else {
            displayedCalories = powerBasedCalories
        }

        let summaryAvgPower = powers.isEmpty ? 0 : powers.reduce(0, +) / powers.count
        let summaryMaxPower = powers.max() ?? 0
        let summaryAvgHR = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / heartRates.count
        let summaryMaxHR = heartRates.max()

        workoutSummary = WorkoutSummary(
            avgPower: summaryAvgPower,
            maxPower: summaryMaxPower,
            totalDistance: computedDistanceMeters,
            totalCalories: displayedCalories,
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
                computedCalories: displayedCalories,
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

        // `watchEnergyKcal` was captured above when computing `displayedCalories` so
        // the in-app summary and the HealthKit `.activeEnergyBurned` sample agree.
        Task {
            if !filteredRemaining.isEmpty {
                await healthKitManager.addSamples(filteredRemaining)
            }
            if !finalHRSamples.isEmpty {
                await healthKitManager.addHeartRateSamples(finalHRSamples)
            }
            await healthKitManager.endWorkout(endDate: endDate, watchEnergyEstimateKcal: watchEnergyKcal, metadata: metadata)
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
        let modality: SessionModality = {
            if let kind = ftpTestKind {
                let sourcePower: Int? = {
                    switch kind {
                    case .twentyMinute: return ftpTestAvgPower
                    case .ramp: return ftpTestBestMinutePower
                    }
                }()
                let result: FTPTestResult? = {
                    guard let measured = computedFTPFromTest, let source = sourcePower else {
                        return nil
                    }
                    return FTPTestResult(measuredFTP: measured, sourcePower: source)
                }()
                return .ftpTest(protocol: kind, result: result)
            }
            return mode.isFreeRide ? .freeRide : .structured
        }()

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
            ftpAtTime: settings.functionalThresholdPower,
            maxHRAtTime: settings.maxHeartRate,
            bikeWasConnected: isConnectedToBike,
            modality: modality
        )

        let snapshots: [SessionInterval] = mode.isFreeRide
            ? []
            : intervals.enumerated().map { index, interval in
                SessionInterval(
                    zone: interval.zone,
                    duration: interval.duration,
                    sortOrder: index
                )
            }
        session.intervals = snapshots

        // If no persister was injected, this is a non-persisting context (e.g. Watch
        // playback or a test fixture); skip persistence silently.
        if let saved = sessionPersister?.save(session, intervals: snapshots) {
            self.savedSession = saved
        }
    }
}
