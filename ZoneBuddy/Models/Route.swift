import Foundation
import SwiftData

/// A single resampled position along an imported route. The full point array
/// is stored as a JSON blob on `Route.pointsData` rather than as @Model children
/// — at ~5m resampling a 60km route is ~12k points, which is too many SwiftData
/// inserts to want to round-trip on every import + CloudKit sync.
struct RoutePoint: Codable, Sendable, Hashable {
    /// Cumulative distance from route start, metres.
    let distanceMeters: Double
    /// Smoothed elevation, metres.
    let elevationMeters: Double
    /// Smoothed grade as a percentage (e.g. 6.5 for 6.5%). Clamped to ±20%.
    let gradePercent: Double
    /// Original latitude/longitude. Retained for a future map overlay; the
    /// simulation loop does not read these and can drop them to shrink the
    /// blob if needed.
    let latitude: Double
    let longitude: Double
}

@Model
final class Route {
    var id: UUID = UUID()
    var name: String = ""
    var importedAt: Date = Date.now
    var sortOrder: Int = 0

    var totalDistanceMeters: Double = 0
    var totalElevationGainMeters: Double = 0
    var totalElevationLossMeters: Double = 0
    var minElevationMeters: Double = 0
    var maxElevationMeters: Double = 0

    /// JSON-encoded `[RoutePoint]`. External storage so the row stays light
    /// and the blob streams in/out of CloudKit as an asset.
    @Attribute(.externalStorage)
    var pointsData: Data = Data()

    /// The original imported GPX bytes. Kept so a future smoothing-algorithm
    /// change can re-derive `pointsData` without forcing a re-import.
    @Attribute(.externalStorage)
    var rawGPX: Data?

    init(
        name: String,
        points: [RoutePoint],
        rawGPX: Data? = nil,
        importedAt: Date = .now
    ) {
        self.name = name
        self.importedAt = importedAt
        self.rawGPX = rawGPX
        self.assignPoints(points)
    }

    /// Decode the points blob. Cheap to call repeatedly; the result is cached
    /// per-instance so the chart, progression cursor, and stats panel can each
    /// read it without paying the JSON decode cost more than once.
    var points: [RoutePoint] {
        if let cached = cachedPoints { return cached }
        guard !pointsData.isEmpty,
              let decoded = try? JSONDecoder().decode([RoutePoint].self, from: pointsData)
        else { return [] }
        cachedPoints = decoded
        return decoded
    }

    /// Re-encode and refresh aggregate stats. Used at import time and would be
    /// used if we ever expose route editing.
    func assignPoints(_ points: [RoutePoint]) {
        cachedPoints = points
        pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        recalculateStats(from: points)
    }

    @Transient
    private var cachedPoints: [RoutePoint]?

    private func recalculateStats(from points: [RoutePoint]) {
        guard !points.isEmpty else {
            totalDistanceMeters = 0
            totalElevationGainMeters = 0
            totalElevationLossMeters = 0
            minElevationMeters = 0
            maxElevationMeters = 0
            return
        }

        totalDistanceMeters = points.last?.distanceMeters ?? 0
        var gain = 0.0
        var loss = 0.0
        var minEle = points[0].elevationMeters
        var maxEle = points[0].elevationMeters
        for i in 1..<points.count {
            let dz = points[i].elevationMeters - points[i - 1].elevationMeters
            if dz > 0 { gain += dz } else { loss += -dz }
            if points[i].elevationMeters < minEle { minEle = points[i].elevationMeters }
            if points[i].elevationMeters > maxEle { maxEle = points[i].elevationMeters }
        }
        totalElevationGainMeters = gain
        totalElevationLossMeters = loss
        minElevationMeters = minEle
        maxElevationMeters = maxEle
    }
}
