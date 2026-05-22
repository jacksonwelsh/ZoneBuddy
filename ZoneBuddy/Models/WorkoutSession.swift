import Foundation
import SwiftData

/// What kind of session a `WorkoutSession` represents. Single source of truth
/// for the modality the UI branches on (history row layout, detail header,
/// power-zone-section visibility, etc.). Adding a new kind of session means
/// adding a case here — no new sibling flags on the model.
enum SessionModality: Codable, Equatable {
    /// A template-driven workout with per-interval prescribed zones.
    case structured
    /// An unstructured ride with no prescribed zones.
    case freeRide
    /// An FTP test (20-min or ramp). `result` is nil when the test ended
    /// without producing a valid FTP (e.g. aborted before any 1-min window).
    case ftpTest(protocol: FTPTestKind, result: FTPTestResult?)
    /// A route ride. Route name + gain are denormalized so the history row
    /// renders even after the user deletes the source `Route`.
    case routeRide(routeID: UUID?, routeName: String, totalElevationGainMeters: Double)
}

/// The output of an FTP test. `measuredFTP` is what the history row displays;
/// `sourcePower` (20-min average, or ramp's best 1-minute rolling average)
/// lets the detail view show the calculation that produced it.
struct FTPTestResult: Codable, Equatable {
    let measuredFTP: Int
    let sourcePower: Int
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()

    var templateID: UUID?
    var name: String = ""
    var transitionWarningDuration: Int = 10

    @Relationship(deleteRule: .cascade, inverse: \SessionInterval.session)
    var intervals: [SessionInterval]?

    var completedAt: Date = Date.now
    var totalDuration: Int = 0

    var avgPower: Int?
    var maxPower: Int?
    var totalOutputKJ: Double?
    var totalDistance: Double?
    var totalCalories: Int?

    var avgHeartRate: Int?
    var maxHeartRate: Int?

    var onTargetZone1Sec: Int = 0
    var onTargetZone2Sec: Int = 0
    var onTargetZone3Sec: Int = 0
    var onTargetZone4Sec: Int = 0
    var onTargetZone5Sec: Int = 0
    var onTargetZone6Sec: Int = 0
    var onTargetZone7Sec: Int = 0

    var scheduledZone1Sec: Int = 0
    var scheduledZone2Sec: Int = 0
    var scheduledZone3Sec: Int = 0
    var scheduledZone4Sec: Int = 0
    var scheduledZone5Sec: Int = 0
    var scheduledZone6Sec: Int = 0
    var scheduledZone7Sec: Int = 0

    var hrZone1Sec: Int = 0
    var hrZone2Sec: Int = 0
    var hrZone3Sec: Int = 0
    var hrZone4Sec: Int = 0
    var hrZone5Sec: Int = 0

    var ftpAtTime: Int?
    var maxHRAtTime: Int?
    var bikeWasConnected: Bool = false

    // MARK: - Modality

    /// JSON-encoded `SessionModality`. The single source of truth for what
    /// kind of session this is and any kind-specific data (e.g. FTP test
    /// result). Adding a new modality = new enum case, no schema migration.
    /// Read/write through `modality`, not directly.
    private var modalityJSON: String?

    /// Pre-modalityJSON storage for free-ride detection. Retained so existing
    /// rows that predate `modalityJSON` still categorize correctly via the
    /// `modality` getter's fallback. All new writes go through `modality`,
    /// which keeps this in sync for any code path we miss. Do not read
    /// directly from outside this file.
    private var _legacyIsFreeRide: Bool = false

    /// The kind of session, with any kind-specific data attached. Set this
    /// after constructing a session to record an FTP test or free ride.
    var modality: SessionModality {
        get {
            if let data = modalityJSON?.data(using: .utf8),
               let value = try? JSONDecoder().decode(SessionModality.self, from: data) {
                return value
            }
            return _legacyIsFreeRide ? .freeRide : .structured
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                modalityJSON = json
            }
            if case .freeRide = newValue {
                _legacyIsFreeRide = true
            } else {
                _legacyIsFreeRide = false
            }
        }
    }

    init(
        templateID: UUID? = nil,
        name: String,
        transitionWarningDuration: Int = 10,
        completedAt: Date = .now,
        totalDuration: Int,
        avgPower: Int? = nil,
        maxPower: Int? = nil,
        totalOutputKJ: Double? = nil,
        totalDistance: Double? = nil,
        totalCalories: Int? = nil,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        onTargetZoneSeconds: [PowerZone: Int] = [:],
        scheduledZoneSeconds: [PowerZone: Int] = [:],
        hrZoneSeconds: [HeartRateZone: Int] = [:],
        ftpAtTime: Int? = nil,
        maxHRAtTime: Int? = nil,
        bikeWasConnected: Bool = false,
        modality: SessionModality = .structured
    ) {
        self.templateID = templateID
        self.name = name
        self.transitionWarningDuration = transitionWarningDuration
        self.completedAt = completedAt
        self.totalDuration = totalDuration
        self.avgPower = avgPower
        self.maxPower = maxPower
        self.totalOutputKJ = totalOutputKJ
        self.totalDistance = totalDistance
        self.totalCalories = totalCalories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate

        self.onTargetZone1Sec = onTargetZoneSeconds[.zone1] ?? 0
        self.onTargetZone2Sec = onTargetZoneSeconds[.zone2] ?? 0
        self.onTargetZone3Sec = onTargetZoneSeconds[.zone3] ?? 0
        self.onTargetZone4Sec = onTargetZoneSeconds[.zone4] ?? 0
        self.onTargetZone5Sec = onTargetZoneSeconds[.zone5] ?? 0
        self.onTargetZone6Sec = onTargetZoneSeconds[.zone6] ?? 0
        self.onTargetZone7Sec = onTargetZoneSeconds[.zone7] ?? 0

        self.scheduledZone1Sec = scheduledZoneSeconds[.zone1] ?? 0
        self.scheduledZone2Sec = scheduledZoneSeconds[.zone2] ?? 0
        self.scheduledZone3Sec = scheduledZoneSeconds[.zone3] ?? 0
        self.scheduledZone4Sec = scheduledZoneSeconds[.zone4] ?? 0
        self.scheduledZone5Sec = scheduledZoneSeconds[.zone5] ?? 0
        self.scheduledZone6Sec = scheduledZoneSeconds[.zone6] ?? 0
        self.scheduledZone7Sec = scheduledZoneSeconds[.zone7] ?? 0

        self.hrZone1Sec = hrZoneSeconds[.zone1] ?? 0
        self.hrZone2Sec = hrZoneSeconds[.zone2] ?? 0
        self.hrZone3Sec = hrZoneSeconds[.zone3] ?? 0
        self.hrZone4Sec = hrZoneSeconds[.zone4] ?? 0
        self.hrZone5Sec = hrZoneSeconds[.zone5] ?? 0

        self.ftpAtTime = ftpAtTime
        self.maxHRAtTime = maxHRAtTime
        self.bikeWasConnected = bikeWasConnected

        self.modality = modality
    }

    var onTargetSecondsByZone: [PowerZone: Int] {
        [
            .zone1: onTargetZone1Sec,
            .zone2: onTargetZone2Sec,
            .zone3: onTargetZone3Sec,
            .zone4: onTargetZone4Sec,
            .zone5: onTargetZone5Sec,
            .zone6: onTargetZone6Sec,
            .zone7: onTargetZone7Sec,
        ]
    }

    var scheduledSecondsByZone: [PowerZone: Int] {
        [
            .zone1: scheduledZone1Sec,
            .zone2: scheduledZone2Sec,
            .zone3: scheduledZone3Sec,
            .zone4: scheduledZone4Sec,
            .zone5: scheduledZone5Sec,
            .zone6: scheduledZone6Sec,
            .zone7: scheduledZone7Sec,
        ]
    }

    var hrSecondsByZone: [HeartRateZone: Int] {
        [
            .zone1: hrZone1Sec,
            .zone2: hrZone2Sec,
            .zone3: hrZone3Sec,
            .zone4: hrZone4Sec,
            .zone5: hrZone5Sec,
        ]
    }

    var sortedIntervals: [SessionInterval] {
        intervals?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }
}
