import Foundation

enum FreeRideGoal: Equatable, Hashable, Codable, Sendable {
    case time(seconds: Int)
    case distance(meters: Double)
}

enum WorkoutMode: Equatable, Sendable {
    case scheduled
    case freeRide(goal: FreeRideGoal?)
    /// Route Ride — plays back an imported GPX route. `routeID` is the
    /// `Route.id` so we can fetch the model at player startup without
    /// dragging a SwiftData object through every layer.
    case routeRide(routeID: UUID)

    var isFreeRide: Bool {
        if case .freeRide = self { return true }
        return false
    }

    var isRouteRide: Bool {
        if case .routeRide = self { return true }
        return false
    }

    /// Unstructured = no prescribed-interval progression. Both free ride and
    /// route ride run on a single open-ended "interval" — the timer drives
    /// distance, not the next scheduled zone.
    var isUnstructured: Bool {
        isFreeRide || isRouteRide
    }

    var goalTimeSeconds: Int? {
        if case .freeRide(let goal) = self, case .time(let s) = goal { return s }
        return nil
    }

    var goalDistanceMeters: Double? {
        if case .freeRide(let goal) = self, case .distance(let m) = goal { return m }
        return nil
    }

    var routeID: UUID? {
        if case .routeRide(let id) = self { return id }
        return nil
    }
}
