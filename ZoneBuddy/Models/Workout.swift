import Foundation
import SwiftData

@Model
final class Workout {
    var name: String = ""
    var createdAt: Date = Date.now
    var sortOrder: Int = 0
    var transitionWarningDuration: Int = SettingsManager.shared.transitionWarningDuration

    @Relationship(deleteRule: .cascade, inverse: \Interval.workout)
    var intervals: [Interval]?

    init(name: String, intervals: [Interval] = [], transitionWarningDuration: Int = SettingsManager.shared.transitionWarningDuration) {
        self.name = name
        self.createdAt = Date()
        self.intervals = intervals
        self.transitionWarningDuration = transitionWarningDuration
    }

    var sortedIntervals: [Interval] {
        intervals?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }

    var totalDuration: Int {
        intervals?.reduce(0) { $0 + $1.duration } ?? 0
    }

    func isCooldown(_ interval: Interval) -> Bool {
        guard let last = sortedIntervals.last else { return false }
        return last.persistentModelID == interval.persistentModelID
            && interval.zone == .zone1
    }
}
