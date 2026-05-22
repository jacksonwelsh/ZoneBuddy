import Foundation

/// Read-only view of the user-controlled settings that the workout player needs.
/// Letting types depend on this protocol — instead of `SettingsManager.shared` — keeps
/// the player view model unit-testable in isolation from the iCloud-backed singleton.
protocol SettingsReading: AnyObject {
    var transitionWarningDuration: Int { get }
    var audioCuesEnabled: Bool { get }
    var functionalThresholdPower: Int { get }
    var maxHeartRate: Int { get }
    /// Rider mass in kilograms. Used by Route Ride mode's virtual-speed
    /// computation: gravity + rolling-resistance contributions are all
    /// proportional to this. Defaults to a typical adult value if unset.
    var riderWeightKg: Double { get }
}

extension SettingsReading {
    var riderWeightKg: Double { 75.0 }
}

extension SettingsManager: SettingsReading {}
