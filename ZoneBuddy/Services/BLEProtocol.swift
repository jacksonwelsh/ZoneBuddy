import CoreBluetooth

/// Shared GATT contract between the iOS/iPad app (peripheral) and the Watch app (central).
/// Both targets include this file so the UUIDs and command bytes have a single definition;
/// previously each side hardcoded its own copy and could silently drift out of sync.
///
/// Marked `nonisolated` because BLE delegate methods (which read these constants) run on
/// CoreBluetooth's internal queue, not the MainActor.
nonisolated enum BLEProtocol {
    static let serviceUUID = CBUUID(string: "B5E5D4A1-4F2C-4C33-9E01-1A2B3C4D5E6F")
    /// Watch → iPad: Watch writes its current heart rate here (1 byte BPM, clamped 0-255).
    static let hrCharUUID = CBUUID(string: "B5E5D4A2-4F2C-4C33-9E01-1A2B3C4D5E6F")
    /// iPad → Watch: iPad notifies the Watch of workout start/pause/resume/end events.
    /// On `startWorkout`, the Watch issues a read to fetch the full WorkoutTransferData payload.
    static let commandCharUUID = CBUUID(string: "B5E5D4A3-4F2C-4C33-9E01-1A2B3C4D5E6F")
    /// Watch → iPad: Watch writes pause/resume/end commands originating from the watch UI.
    static let watchCommandCharUUID = CBUUID(string: "B5E5D4A4-4F2C-4C33-9E01-1A2B3C4D5E6F")
    /// Watch → host: 2-byte little-endian Int16 delta watts. Host applies via
    /// `TrainerController.adjustTargetWatts(by:)`. Used for Digital Crown
    /// adjustments while a workout is running.
    static let trainerAdjustCharUUID = CBUUID(string: "B5E5D4A5-4F2C-4C33-9E01-1A2B3C4D5E6F")

    static let advertisedLocalName = "ZoneBuddy"
}

/// Command bytes exchanged over the workout-command characteristics. Direction is documented
/// per case — same enum is used on both sides of the wire to prevent magic-number drift.
nonisolated enum BLECommand: UInt8 {
    case startWorkout = 0x01
    case pauseWorkout = 0x02
    case resumeWorkout = 0x03
    case endWorkout = 0x04
}
