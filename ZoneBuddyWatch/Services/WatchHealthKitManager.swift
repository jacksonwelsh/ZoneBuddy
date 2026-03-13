import Foundation
import HealthKit

@Observable
final class WatchHealthKitManager: HealthKitWorkoutRecording, HeartRateStreaming {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var latestHeartRate: Int?
    private(set) var liveCalories: Double? = nil
    private var hrQuery: HKAnchoredObjectQuery?
    private var builderDelegate: BuilderDelegate?

    // MARK: - HealthKitWorkoutRecording

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            print("WatchHealthKit authorization error: \(error)")
            return false
        }
    }

    func startWorkout(startDate: Date) async -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            let delegate = BuilderDelegate { [weak self] calories in
                Task { @MainActor [weak self] in
                    self?.liveCalories = calories
                }
            }
            builder.delegate = delegate

            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            self.session = session
            self.builder = builder
            self.builderDelegate = delegate
            return true
        } catch {
            print("WatchHealthKit start workout error: \(error)")
            return false
        }
    }

    func addSamples(_ samples: [BikeDataSample]) async {
        // No bike data on watch — HR is collected automatically by HKLiveWorkoutBuilder
    }

    func endWorkout(endDate: Date, metadata: [String: Any]) async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        self.builderDelegate = nil

        session.end()
        do {
            try await builder.endCollection(at: endDate)
            if !metadata.isEmpty {
                try await builder.addMetadata(metadata)
            }
            try await builder.finishWorkout()
        } catch {
            print("WatchHealthKit end workout error: \(error)")
        }
    }

    // MARK: - HeartRateStreaming

    func startMonitoring(from startDate: Date) {
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

        hrQuery = query
        healthStore.execute(query)
    }

    func stopMonitoring() {
        if let hrQuery {
            healthStore.stop(hrQuery)
        }
        hrQuery = nil
        latestHeartRate = nil
    }

    private func processSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }

        let bpm = Int(latest.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in
            self.latestHeartRate = bpm
        }
    }

    // MARK: - Builder Delegate

    private class BuilderDelegate: NSObject, HKLiveWorkoutBuilderDelegate {
        let onCaloriesUpdate: @Sendable (Double) -> Void

        init(onCaloriesUpdate: @escaping @Sendable (Double) -> Void) {
            self.onCaloriesUpdate = onCaloriesUpdate
        }

        nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

        nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
            let energyType = HKQuantityType(.activeEnergyBurned)
            guard collectedTypes.contains(energyType),
                  let stats = workoutBuilder.statistics(for: energyType),
                  let sum = stats.sumQuantity() else { return }

            let kcal = sum.doubleValue(for: .kilocalorie())
            onCaloriesUpdate(kcal)
        }
    }
}
