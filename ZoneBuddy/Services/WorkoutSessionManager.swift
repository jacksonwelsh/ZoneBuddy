import Foundation
import Observation

@Observable
final class WorkoutSessionManager {
    static let shared = WorkoutSessionManager()
    
    var activeViewModel: WorkoutPlayerViewModel?
    
    private init() {}
}
