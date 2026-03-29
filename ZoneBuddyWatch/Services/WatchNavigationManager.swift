import Foundation

@Observable
final class WatchNavigationManager {
    static let shared = WatchNavigationManager()

    var pendingWorkout: WorkoutTransferData?
    var shouldStartWorkout = false

    private init() {}

    func reset() {
        pendingWorkout = nil
        shouldStartWorkout = false
    }
}
