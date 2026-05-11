import Foundation
import HealthKit

final class LiveHealthKitWorkoutManager: HealthKitWorkoutRecording {
    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?

    var liveCalories: Double? { nil }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
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
            return true
        } catch {
            print("HealthKit start workout error: \(error)")
            return false
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

        // Batch-level energy and distance: same physics used by the live view-model totals,
        // so the workout summary and HealthKit record always agree.
        if let kcal = WorkoutSampleAggregator.estimatedCalories(in: samples), kcal > 0 {
            hkSamples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                start: samples.first!.timestamp,
                end: samples.last!.timestamp
            ))
        }

        let (meters, _) = WorkoutSampleAggregator.integrateDistance(in: samples, startingFrom: nil)
        if meters > 0 {
            hkSamples.append(HKQuantitySample(
                type: HKQuantityType(.distanceCycling),
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: samples.first!.timestamp,
                end: samples.last!.timestamp
            ))
        }

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

    func endWorkout(endDate: Date, metadata: [String: Any]) async {
        guard let builder = workoutBuilder else { return }
        workoutBuilder = nil

        do {
            try await builder.endCollection(at: endDate)
            if !metadata.isEmpty {
                try await builder.addMetadata(metadata)
            }
            try await builder.finishWorkout()
        } catch {
            print("HealthKit end workout error: \(error)")
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
