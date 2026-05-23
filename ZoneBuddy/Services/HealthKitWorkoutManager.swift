import Foundation
import HealthKit
import CoreLocation

final class LiveHealthKitWorkoutManager: HealthKitWorkoutRecording {
    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var routeLocationCount: Int = 0

    // Energy and distance are accumulated across all flush batches and written as
    // a single sample at endWorkout. Per-batch writes truncated kcal to Int and
    // restarted integration with no continuity, dropping ~50–150 kcal and noticeable
    // distance over a typical ride. One summary sample keeps the HK record in lockstep
    // with the in-app session totals.
    private var workoutStartDate: Date?
    private var lastSampleDate: Date?
    private var accumulatedJoules: Double = 0
    private var accumulatedMeters: Double = 0

    var liveCalories: Double? { nil }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.cyclingCadence),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            print("HealthKit authorization error: \(error)")
            return false
        }
    }

    func startWorkout(startDate: Date) async -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor

        do {
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
            try await builder.beginCollection(at: startDate)
            workoutBuilder = builder
            workoutStartDate = startDate
            lastSampleDate = nil
            accumulatedJoules = 0
            accumulatedMeters = 0
            routeBuilder = nil
            routeLocationCount = 0
            return true
        } catch {
            print("HealthKit start workout error: \(error)")
            return false
        }
    }

    func beginRouteRecording() async {
        guard workoutBuilder != nil, routeBuilder == nil else { return }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        routeLocationCount = 0
    }

    func addRouteLocations(_ locations: [CLLocation]) async {
        guard let routeBuilder, !locations.isEmpty else { return }
        do {
            try await routeBuilder.insertRouteData(locations)
            routeLocationCount += locations.count
        } catch {
            print("HealthKit insertRouteData error: \(error)")
        }
    }

    func addSamples(_ samples: [BikeDataSample]) async {
        guard let builder = workoutBuilder, !samples.isEmpty else { return }

        var hkSamples: [HKQuantitySample] = []

        for sample in samples {
            let date = sample.timestamp

            if let power = sample.power {
                hkSamples.append(HKQuantitySample(
                    type: HKQuantityType(.cyclingPower),
                    quantity: HKQuantity(unit: .watt(), doubleValue: Double(power)),
                    start: date,
                    end: date
                ))
            }

            if let cadence = sample.cadence {
                // HealthKit cycling cadence is in count/min
                hkSamples.append(HKQuantitySample(
                    type: HKQuantityType(.cyclingCadence),
                    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: cadence),
                    start: date,
                    end: date
                ))
            }

            if let hr = sample.heartRate, hr > 0 {
                hkSamples.append(HKQuantitySample(
                    type: HKQuantityType(.heartRate),
                    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(hr)),
                    start: date,
                    end: date
                ))
            }
        }

        // Accumulate joules and meters across batches; the single summary sample
        // covering the whole workout is added at endWorkout.
        let (batchJoules, _) = WorkoutSampleAggregator.integrateJoules(in: samples, startingFrom: lastSampleDate)
        accumulatedJoules += batchJoules
        let (batchMeters, _) = WorkoutSampleAggregator.integrateDistance(in: samples, startingFrom: lastSampleDate)
        accumulatedMeters += batchMeters
        lastSampleDate = samples.last?.timestamp ?? lastSampleDate

        guard !hkSamples.isEmpty else { return }

        do {
            try await builder.addSamples(hkSamples)
        } catch {
            print("HealthKit addSamples error: \(error)")
        }
    }

    func addHeartRateSamples(_ samples: [(bpm: Int, date: Date)]) async {
        guard let builder = workoutBuilder, !samples.isEmpty else { return }

        let hkSamples = samples.map { sample in
            HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(sample.bpm)),
                start: sample.date,
                end: sample.date
            )
        }

        do {
            try await builder.addSamples(hkSamples)
        } catch {
            print("HealthKit addHeartRateSamples error: \(error)")
        }
    }

    func pauseWorkout() {
        guard let builder = workoutBuilder else { return }
        let event = HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: Date(), duration: 0), metadata: nil)
        Task {
            do {
                try await builder.addWorkoutEvents([event])
            } catch {
                print("HealthKit addWorkoutEvents(.pause) error: \(error)")
            }
        }
    }

    func resumeWorkout() {
        guard let builder = workoutBuilder else { return }
        let event = HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: Date(), duration: 0), metadata: nil)
        Task {
            do {
                try await builder.addWorkoutEvents([event])
            } catch {
                print("HealthKit addWorkoutEvents(.resume) error: \(error)")
            }
        }
    }

    func endWorkout(endDate: Date, watchEnergyEstimateKcal: Double?, metadata: [String: Any]) async {
        guard let builder = workoutBuilder, let startDate = workoutStartDate else { return }
        workoutBuilder = nil
        let totalJoules = accumulatedJoules
        let totalMeters = accumulatedMeters
        workoutStartDate = nil
        lastSampleDate = nil
        accumulatedJoules = 0
        accumulatedMeters = 0

        var summarySamples: [HKQuantitySample] = []
        let powerBasedKcal = totalJoules / (WorkoutSampleAggregator.cyclingEfficiency * 4184.0)
        // The Move ring credits only a workout's attached active-energy samples for the
        // workout window — any ambient Watch HR-based samples in that range are deduped
        // out, and the Watch's `HKWorkoutSession` pauses ambient tracking anyway and
        // discards its own HR-based samples when we don't save its workout. Writing only
        // the (lower) power-based number strictly reduces the ring vs. what the Watch
        // would have credited. Take `max(power, HR)` so the ring never loses calories.
        let activeKcal = max(powerBasedKcal, watchEnergyEstimateKcal ?? 0)
        if activeKcal > 0 {
            summarySamples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: activeKcal),
                start: startDate,
                end: endDate
            ))
        }
        if totalMeters > 0 {
            summarySamples.append(HKQuantitySample(
                type: HKQuantityType(.distanceCycling),
                quantity: HKQuantity(unit: .meter(), doubleValue: totalMeters),
                start: startDate,
                end: endDate
            ))
        }

        // Preserve both source values in metadata so the in-app summary can show the
        // power-based number even when the HealthKit sample reflects the higher of the two.
        var enrichedMetadata = metadata
        enrichedMetadata["ZoneBuddyPowerBasedKcal"] = powerBasedKcal
        if let watchKcal = watchEnergyEstimateKcal {
            enrichedMetadata["ZoneBuddyWatchHRKcal"] = watchKcal
        }

        // Capture and clear the route builder up front so we can finalize it
        // after `finishWorkout` returns the saved HKWorkout. Apple requires
        // `finishRoute(with:metadata:)` to be called AFTER the workout exists
        // in the HealthKit store — reversing the order returns an
        // "associated workout not found" error and the route is orphaned.
        let pendingRouteBuilder = routeBuilder
        let pendingRouteCount = routeLocationCount
        routeBuilder = nil
        routeLocationCount = 0

        var savedWorkout: HKWorkout?
        do {
            if !summarySamples.isEmpty {
                try await builder.addSamples(summarySamples)
            }
            try await builder.endCollection(at: endDate)
            if !enrichedMetadata.isEmpty {
                try await builder.addMetadata(enrichedMetadata)
            }
            savedWorkout = try await builder.finishWorkout()
        } catch {
            print("HealthKit end workout error: \(error)")
        }

        if let savedWorkout, let pendingRouteBuilder, pendingRouteCount > 0 {
            var routeMetadata: [String: Any] = [:]
            if let gain = enrichedMetadata[HKMetadataKeyElevationAscended] {
                routeMetadata[HKMetadataKeyElevationAscended] = gain
            }
            if let loss = enrichedMetadata[HKMetadataKeyElevationDescended] {
                routeMetadata[HKMetadataKeyElevationDescended] = loss
            }
            do {
                _ = try await pendingRouteBuilder.finishRoute(with: savedWorkout, metadata: routeMetadata.isEmpty ? nil : routeMetadata)
            } catch {
                print("HealthKit finishRoute error: \(error)")
            }
        }
    }
}

/// Streams heart rate from HealthKit using an anchored object query.
/// Picks up data from Apple Watch, AirPods Pro, or any connected HR sensor.
/// Authorization must be requested separately before calling `startMonitoring`.
@Observable
final class LiveHeartRateStreamer: HeartRateStreaming {
    private(set) var latestHeartRate: Int?

    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?

    func startMonitoring(from startDate: Date) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Stop any existing query before starting a new one
        stopMonitoring()

        let hrType = HKQuantityType(.heartRate)

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processSamples(samples)
        }

        self.query = query
        healthStore.execute(query)
    }

    private func processSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }

        let bpm = Int(latest.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in
            self.latestHeartRate = bpm
        }
    }

    func stopMonitoring() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
        latestHeartRate = nil
    }
}
