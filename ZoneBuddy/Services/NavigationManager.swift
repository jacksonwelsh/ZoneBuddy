import SwiftUI
import Observation

@Observable
final class NavigationManager {
    static let shared = NavigationManager()
    
    var selectedWorkout: Workout?
    var shouldStartWorkout: Bool = false
    
    private init() {}
    
    func startWorkout(_ workout: Workout) {
        selectedWorkout = workout
        shouldStartWorkout = true
    }
}
