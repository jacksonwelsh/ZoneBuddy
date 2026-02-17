import ActivityKit
import Foundation

nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    let workoutName: String
    let totalIntervals: Int

    nonisolated struct ContentState: Codable, Hashable {
        let currentZoneRawValue: Int?
        let currentLabel: String
        let currentIntervalIndex: Int
        let nextZoneRawValue: Int?
        let upcomingLabel: String
        let intervalStartDate: Date?
        let intervalEndDate: Date?
        let secondsRemaining: Int
        let intervalProgress: Double
        let isRunning: Bool
        let isFinished: Bool
    }
}
