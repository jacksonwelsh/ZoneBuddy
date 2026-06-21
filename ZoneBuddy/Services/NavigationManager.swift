import SwiftUI
import Observation

@Observable
final class NavigationManager {
    static let shared = NavigationManager()
    
    var selectedWorkout: Workout?
    var shouldStartWorkout: Bool = false

    /// Set when an external action (e.g. opening a GPX file via the system
    /// "Open with ZoneBuddy" handler) has imported a route that should be
    /// previewed. `WorkoutLibraryView` consumes this and pushes the preview.
    var routeToPreview: Route?

    private init() {}
    
    func startWorkout(_ workout: Workout) {
        selectedWorkout = workout
        shouldStartWorkout = true
    }
}
