import Foundation

/// Centralizes the physics math for converting a series of `BikeDataSample`s into
/// distance, total mechanical output (kJ), and calorie estimates.
///
/// Before this type existed the same integration loops were inlined in three places
/// (`WorkoutPlayerViewModel.currentTotalOutputKJ`, the same VM's `finishHealthKitWorkout`,
/// and `LiveHealthKitWorkoutManager.addSamples`) — making it easy for the formulas to
/// silently drift. Routing everyone through `WorkoutSampleAggregator` keeps them aligned.
enum WorkoutSampleAggregator {
    /// Reject sample-to-sample time gaps longer than this. Long gaps indicate a pause,
    /// a disconnect, or test data — integrating across them would inflate totals.
    private static let maxIntegrationGapSeconds: TimeInterval = 30

    /// Gross mechanical efficiency of cycling. Used to convert mechanical kJ output into
    /// metabolic kcal: kcal = joules / (efficiency × 4184).
    static let cyclingEfficiency: Double = 0.25

    /// Integrate power (watts) × time (s) over consecutive samples to compute total joules.
    /// Returns `nil` when fewer than two samples are present.
    static func totalJoules(in samples: [BikeDataSample]) -> Double? {
        guard samples.count > 1 else { return nil }
        var joules: Double = 0
        for i in 1..<samples.count {
            guard let power = samples[i].power else { continue }
            let dt = samples[i].timestamp.timeIntervalSince(samples[i - 1].timestamp)
            guard dt > 0, dt < maxIntegrationGapSeconds else { continue }
            joules += Double(power) * dt
        }
        return joules
    }

    /// Mechanical output in kilojoules across the sample run.
    static func totalOutputKJ(in samples: [BikeDataSample]) -> Double? {
        guard let joules = totalJoules(in: samples), joules > 0 else { return nil }
        return joules / 1000.0
    }

    /// Estimated active calories burned using the cycling-efficiency model.
    static func estimatedCalories(in samples: [BikeDataSample]) -> Int? {
        guard let joules = totalJoules(in: samples), joules > 0 else { return nil }
        return Int(joules / (cyclingEfficiency * 4184.0))
    }

    /// Integrate speed (km/h) over time to accumulate meters traveled, optionally extending
    /// a running total whose last timestamp is tracked outside the call.
    /// - Returns: A tuple of the additional meters and the timestamp of the final sample
    ///   used, so the caller can resume integration from that point on the next batch.
    static func integrateDistance(
        in samples: [BikeDataSample],
        startingFrom lastSampleDate: Date?
    ) -> (meters: Double, lastSampleDate: Date?) {
        var meters: Double = 0
        var previousDate = lastSampleDate
        for sample in samples {
            if let speed = sample.speed, let prev = previousDate {
                let dt = sample.timestamp.timeIntervalSince(prev)
                if dt > 0, dt < maxIntegrationGapSeconds {
                    let metersPerSecond = speed * 1000.0 / 3600.0
                    meters += metersPerSecond * dt
                }
            }
            previousDate = sample.timestamp
        }
        return (meters, previousDate)
    }
}
