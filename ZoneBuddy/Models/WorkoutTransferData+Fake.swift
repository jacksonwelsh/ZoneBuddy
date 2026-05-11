#if DEBUG
import Foundation

extension WorkoutTransferData {
    /// Hardcoded sample workout used by the Watch app when launched with
    /// `ZB_SIMULATOR_FAKES=1` so its UI can be exercised without a paired
    /// iPhone or any real workout being sent over WCSession.
    ///
    /// Structure: warmup (Z1) → Z2 → Z4 → Z2 → Z1 cooldown, 5 minutes each.
    static var fakeSample: WorkoutTransferData {
        WorkoutTransferData(
            name: "Fake Sim Workout",
            transitionWarningDuration: 5,
            intervals: [
                IntervalTransferData(zone: 1, duration: 5 * 60),
                IntervalTransferData(zone: 2, duration: 5 * 60),
                IntervalTransferData(zone: 4, duration: 5 * 60),
                IntervalTransferData(zone: 2, duration: 5 * 60),
                IntervalTransferData(zone: 1, duration: 5 * 60),
            ],
            startedAt: Date()
        )
    }
}
#endif
