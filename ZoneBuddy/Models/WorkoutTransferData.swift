import Foundation

struct IntervalTransferData: Codable, Sendable {
    var zone: Int?
    var duration: Int

    enum CodingKeys: String, CodingKey {
        case zone = "z"
        case duration = "d"
    }
}

struct WorkoutTransferData: Codable, Identifiable, Sendable {
    var name: String
    var transitionWarningDuration: Int
    var intervals: [IntervalTransferData]
    var startedAt: Date?

    var id: String { name + intervals.map { "\($0.zone ?? -1):\($0.duration)" }.joined() }

    enum CodingKeys: String, CodingKey {
        case name = "n"
        case transitionWarningDuration = "t"
        case intervals = "i"
        case startedAt = "s"
    }

    init(workout: Workout) {
        self.name = workout.name
        self.transitionWarningDuration = workout.transitionWarningDuration
        self.intervals = workout.sortedIntervals.map {
            IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
        }
    }

    init(name: String, transitionWarningDuration: Int, intervals: [IntervalTransferData], startedAt: Date? = nil) {
        self.name = name
        self.transitionWarningDuration = transitionWarningDuration
        self.intervals = intervals
        self.startedAt = startedAt
    }

    var totalDuration: Int {
        intervals.reduce(0) { $0 + $1.duration }
    }
}
