import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Interval.workout)
    var intervals: [Interval]

    init(name: String, intervals: [Interval] = []) {
        self.name = name
        self.createdAt = Date()
        self.intervals = intervals
    }

    var sortedIntervals: [Interval] {
        intervals.sorted { $0.sortOrder < $1.sortOrder }
    }

    var totalDuration: Int {
        intervals.reduce(0) { $0 + $1.duration }
    }

    func isCooldown(_ interval: Interval) -> Bool {
        guard let last = sortedIntervals.last else { return false }
        return last.persistentModelID == interval.persistentModelID
            && interval.zone == .zone1
    }
}
