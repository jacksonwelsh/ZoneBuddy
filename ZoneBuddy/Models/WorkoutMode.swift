import Foundation

enum FreeRideGoal: Equatable, Hashable, Codable, Sendable {
    case time(seconds: Int)
    case distance(meters: Double)
}

enum WorkoutMode: Equatable, Sendable {
    case scheduled
    case freeRide(goal: FreeRideGoal?)

    var isFreeRide: Bool {
        if case .freeRide = self { return true }
        return false
    }

    var goalTimeSeconds: Int? {
        if case .freeRide(let goal) = self, case .time(let s) = goal { return s }
        return nil
    }

    var goalDistanceMeters: Double? {
        if case .freeRide(let goal) = self, case .distance(let m) = goal { return m }
        return nil
    }
}
