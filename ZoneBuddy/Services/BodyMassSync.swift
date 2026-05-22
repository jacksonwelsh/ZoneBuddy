import Foundation
import HealthKit

/// Reads the most recent body-mass sample from HealthKit and returns it in
/// kilograms. Requests read authorization on demand — the user can decline,
/// in which case the result is nil and the caller falls back to the
/// settings-stored value.
@MainActor
enum BodyMassSync {
    /// Returns the most recent body-mass sample (kg), or nil if HealthKit
    /// is unavailable, the user declined, or no sample has ever been written.
    static func latestBodyMassKg() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        let bodyMassType = HKQuantityType(.bodyMass)

        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMassType])
        } catch {
            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = (samples?.first as? HKQuantitySample) else {
                    continuation.resume(returning: nil)
                    return
                }
                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }
}
