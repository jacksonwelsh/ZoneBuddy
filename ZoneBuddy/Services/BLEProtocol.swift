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
    /// Bidirectional absolute trainer-target channel.
    /// Payload: 2-byte little-endian Int16.
    ///   `>= 0` — absolute target watts (host is in or will enter ERG mode at this value).
    ///   `-1`   — sentinel meaning "no target" (host is not in ERG mode).
    /// Direction:
    ///   Watch → host writes: requested absolute target (host applies via `setTargetWatts`).
    ///   Host  → Watch notify/read: current `TrainerController.currentTargetWatts`.
    /// The Watch reads on connect and subscribes for notifies so it always knows the
    /// true current value and can compute an accurate new target as the Crown turns.
    static let trainerTargetCharUUID = CBUUID(string: "B5E5D4A5-4F2C-4C33-9E01-1A2B3C4D5E6F")
    /// Watch → iPad: cumulative HR-based active-energy estimate, in kilocalories.
    /// Payload: 2-byte little-endian UInt16. Watch writes whenever its
    /// `HKLiveWorkoutBuilder` posts an updated `.activeEnergyBurned` statistic.
    /// The iPad uses the latest received value at workout end to top up the
    /// HealthKit "Total Calories" via a `.basalEnergyBurned` delta sample when
    /// the Watch's estimate exceeds the power-based active calculation.
    static let watchEnergyCharUUID = CBUUID(string: "B5E5D4A6-4F2C-4C33-9E01-1A2B3C4D5E6F")

    /// Sentinel for "no current target" on the trainer-target characteristic.
    static let trainerTargetNoneSentinel: Int16 = -1

    /// Bidirectional absolute trainer-resistance channel. Mirrors `trainerTargetCharUUID`
    /// for manual-resistance (Level) mode.
    ///
    /// Host → Watch notify/read payload: 6 bytes, three little-endian Int16s:
    ///   bytes 0–1: current resistance level (`-1` = "not in Level mode").
    ///   bytes 2–3: minimum supported level (`-1` = "unknown").
    ///   bytes 4–5: maximum supported level (`-1` = "unknown").
    /// Bounds are persistent capabilities of the bike, so the host publishes them whenever
    /// they're known — even while in ERG — so the Watch can clamp Crown input the moment
    /// the rider switches to Level.
    ///
    /// Watch → host write payload: 2 bytes, little-endian Int16, absolute level (`>= 0`).
    /// The Watch only writes here when the host has already published a non-nil current
    /// level, so this never switches the host's active mode.
    static let trainerResistanceCharUUID = CBUUID(string: "B5E5D4A7-4F2C-4C33-9E01-1A2B3C4D5E6F")

    /// Sentinel for "not in Level mode" / "bound unknown" on the trainer-resistance characteristic.
    static let trainerResistanceNoneSentinel: Int16 = -1

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
