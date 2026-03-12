import Foundation

@Observable
final class WatchNavigationManager {
    static let shared = WatchNavigationManager()

    var pendingWorkout: WorkoutTransferData?
    var shouldStartWorkout = false
    var shouldDismissWorkout = false

    private init() {}

    func reset() {
        pendingWorkout = nil
        shouldStartWorkout = false
        shouldDismissWorkout = false
    }
}
