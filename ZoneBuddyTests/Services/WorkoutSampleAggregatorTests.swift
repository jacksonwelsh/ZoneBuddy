import Testing
import Foundation
@testable import ZoneBuddy

struct WorkoutSampleAggregatorTests {
    private func sample(at t: TimeInterval, power: Int? = nil, speed: Double? = nil) -> BikeDataSample {
        BikeDataSample(
            timestamp: Date(timeIntervalSince1970: t),
            power: power,
            cadence: nil,
            heartRate: nil,
            speed: speed,
            distance: nil,
            calories: nil
        )
    }

    @Test
    func returnsNilForEmptyOrSingleSample() {
        #expect(WorkoutSampleAggregator.totalJoules(in: []) == nil)
        #expect(WorkoutSampleAggregator.totalJoules(in: [sample(at: 0, power: 100)]) == nil)
        #expect(WorkoutSampleAggregator.totalOutputKJ(in: []) == nil)
        #expect(WorkoutSampleAggregator.estimatedCalories(in: []) == nil)
    }

    @Test
    func integratesPowerOverTime() {
        // 100W held for 10 seconds = 1000 joules = 1 kJ
        let samples = [sample(at: 0, power: 100), sample(at: 10, power: 100)]
        #expect(WorkoutSampleAggregator.totalJoules(in: samples) == 1000)
        #expect(WorkoutSampleAggregator.totalOutputKJ(in: samples) == 1.0)
    }

    @Test
    func dropsGapsLongerThan30Seconds() {
        // Two 100W samples 60 seconds apart: integration should reject the gap, returning 0 joules.
        let samples = [sample(at: 0, power: 100), sample(at: 60, power: 100)]
        #expect(WorkoutSampleAggregator.totalJoules(in: samples) == 0)
        // 0 joules means no output / no calories surfaced
        #expect(WorkoutSampleAggregator.totalOutputKJ(in: samples) == nil)
        #expect(WorkoutSampleAggregator.estimatedCalories(in: samples) == nil)
    }

    @Test
    func caloriesUseTwentyFivePercentEfficiency() {
        // 1000 joules / (0.25 * 4184) ≈ 0.956 kcal → Int truncates to 0
        let smallSamples = [sample(at: 0, power: 100), sample(at: 10, power: 100)]
        #expect(WorkoutSampleAggregator.estimatedCalories(in: smallSamples) == 0)

        // 200W × 60s = 12,000 joules → 12000 / (0.25*4184) ≈ 11.47 kcal → 11
        let biggerSamples = [sample(at: 0, power: 200), sample(at: 60, power: 200)]
        // Gap of 60s — too large; result should be nil. Use 25s instead.
        let validBigger = [sample(at: 0, power: 200), sample(at: 25, power: 200)]
        #expect(WorkoutSampleAggregator.estimatedCalories(in: validBigger) == Int(200.0 * 25.0 / (0.25 * 4184.0)))
        // (sanity) — confirm gap-rejected case
        #expect(WorkoutSampleAggregator.estimatedCalories(in: biggerSamples) == nil)
    }

    @Test
    func distanceIntegratesSpeed() {
        // 36 km/h = 10 m/s. Held for 10s → 100 meters.
        let samples = [sample(at: 0, speed: 36.0), sample(at: 10, speed: 36.0)]
        let (meters, last) = WorkoutSampleAggregator.integrateDistance(in: samples, startingFrom: nil)
        // First sample has no predecessor, so only the 2nd contributes: 10s × 10 m/s = 100m.
        #expect(meters == 100.0)
        #expect(last == samples.last?.timestamp)
    }

    @Test
    func distanceResumesFromPriorTimestamp() {
        let first = sample(at: 100, speed: 36.0)
        let priorDate = Date(timeIntervalSince1970: 95) // 5 seconds before
        let (meters, _) = WorkoutSampleAggregator.integrateDistance(in: [first], startingFrom: priorDate)
        // 5s × 10 m/s = 50m
        #expect(meters == 50.0)
    }

    @Test
    func integrateJoulesAcrossBatchesMatchesConcatenated() {
        // 100 samples at 1Hz, constant 150W. Split into 10 batches of 10 samples each.
        // The per-batch integration with continuity must match integrating the full stream.
        let full = (0..<100).map { sample(at: TimeInterval($0), power: 150) }
        let referenceJoules = WorkoutSampleAggregator.totalJoules(in: full) ?? -1

        var accumulated: Double = 0
        var lastDate: Date? = nil
        for batchStart in stride(from: 0, to: 100, by: 10) {
            let batch = Array(full[batchStart..<batchStart + 10])
            let (batchJoules, last) = WorkoutSampleAggregator.integrateJoules(in: batch, startingFrom: lastDate)
            accumulated += batchJoules
            lastDate = last
        }

        #expect(accumulated == referenceJoules)
        // Sanity: not zero
        #expect(referenceJoules > 0)
    }

    @Test
    func integrateJoulesRejectsLongGaps() {
        // Two samples 60s apart — gap exceeds maxIntegrationGapSeconds; joules must be 0.
        let samples = [sample(at: 0, power: 200), sample(at: 60, power: 200)]
        let (joules, _) = WorkoutSampleAggregator.integrateJoules(in: samples, startingFrom: nil)
        #expect(joules == 0)
    }
}
