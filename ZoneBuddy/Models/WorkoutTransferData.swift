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

    /// nil/"scheduled" = current behavior. "freeride" = open-ended ride with optional goal.
    var mode: String?
    var goalDurationSec: Int?
    var goalDistanceMeters: Double?

    var id: String { name + intervals.map { "\($0.zone ?? -1):\($0.duration)" }.joined() }

    enum CodingKeys: String, CodingKey {
        case name = "n"
        case transitionWarningDuration = "t"
        case intervals = "i"
        case startedAt = "s"
        case mode = "m"
        case goalDurationSec = "gd"
        case goalDistanceMeters = "gdm"
    }

    init(workout: Workout) {
        self.name = workout.name
        self.transitionWarningDuration = workout.transitionWarningDuration
        self.intervals = workout.sortedIntervals.map {
            IntervalTransferData(zone: $0.zoneRawValue, duration: $0.duration)
        }
    }

    init(
        name: String,
        transitionWarningDuration: Int,
        intervals: [IntervalTransferData],
        startedAt: Date? = nil,
        mode: String? = nil,
        goalDurationSec: Int? = nil,
        goalDistanceMeters: Double? = nil
    ) {
        self.name = name
        self.transitionWarningDuration = transitionWarningDuration
        self.intervals = intervals
        self.startedAt = startedAt
        self.mode = mode
        self.goalDurationSec = goalDurationSec
        self.goalDistanceMeters = goalDistanceMeters
    }

    var totalDuration: Int {
        intervals.reduce(0) { $0 + $1.duration }
    }

    /// True when this packet describes a Free Ride (no scheduled intervals).
    var isFreeRide: Bool { mode == "freeride" }
}
