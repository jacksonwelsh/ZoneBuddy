import Foundation

enum ConnectivityMessage {
    static let startWorkout = "startWorkout"
    static let heartRate = "heartRate"
    static let workoutEnded = "workoutEnded"

    static let payloadKey = "payload"
    static let bpmKey = "bpm"
    static let timestampKey = "timestamp"
}
