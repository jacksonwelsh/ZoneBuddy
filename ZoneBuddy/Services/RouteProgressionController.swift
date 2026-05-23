import Foundation
import FTMSKit

/// Interpolated position along a route at the current playback cursor. Carries
/// everything needed to materialize an HKWorkoutRoute `CLLocation`.
struct RoutePositionSnapshot: Sendable, Equatable {
    let distanceMeters: Double
    let elevationMeters: Double
    let latitude: Double
    let longitude: Double
    let gradePercent: Double
}

/// Drives a `Route` playback during a Route Ride: integrates measured speed
/// from a connected trainer into a position along the route, looks up the
/// smoothed grade at that position, and pushes it to the trainer in
/// simulation mode.
///
/// The controller does NOT own a timer. The hosting view model (which
/// already runs a 1Hz timer for the workout clock) calls `tick(now:)` once
/// per tick — keeping a single source of truth for time so we don't drift.
@Observable
@MainActor
final class RouteProgressionController {

    let route: Route
    private(set) var distanceMeters: Double = 0
    private(set) var elevationGainMeters: Double = 0
    private(set) var elevationLossMeters: Double = 0
    private(set) var currentGradePercent: Double = 0
    private(set) var isFinished: Bool = false
    /// Monotonic cursor into `route.points`. Advanced O(1) per tick.
    private(set) var currentPointIndex: Int = 0

    // Strong references: `BikeConnecting` and `TrainerControlling` are
    // existential-Observable protocols and aren't class-bound, so a `weak`
    // store is not possible. The route controller is owned by the player VM
    // and torn down at workout end, so retain cycles are avoided by lifetime.
    @ObservationIgnored private var trainerController: (any TrainerControlling)?
    @ObservationIgnored private var bikeManager: (any BikeConnecting)?
    @ObservationIgnored private var settings: (any SettingsReading)?
    @ObservationIgnored private let dateProvider: @MainActor () -> Date
    @ObservationIgnored private var lastTickDate: Date?
    @ObservationIgnored private let routePoints: [RoutePoint]

    init(
        route: Route,
        trainerController: (any TrainerControlling)?,
        bikeManager: (any BikeConnecting)?,
        settings: (any SettingsReading)? = nil,
        dateProvider: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.route = route
        self.trainerController = trainerController
        self.bikeManager = bikeManager
        self.settings = settings
        self.dateProvider = dateProvider
        // Cache the decoded array once — the property accessor decodes from
        // the SwiftData blob on first read, and the tick loop should not
        // re-pay that cost.
        self.routePoints = route.points
        if let first = routePoints.first {
            self.currentGradePercent = first.gradePercent
        }
    }

    var remainingMeters: Double {
        max(0, route.totalDistanceMeters - distanceMeters)
    }

    var progressFraction: Double {
        guard route.totalDistanceMeters > 0 else { return 0 }
        return min(1, max(0, distanceMeters / route.totalDistanceMeters))
    }

    /// Called by the VM when the workout starts. Drops the trainer into sim
    /// mode at the starting grade.
    func begin() async {
        lastTickDate = nil
        if let first = routePoints.first {
            currentGradePercent = first.gradePercent
            await trainerController?.enterSimulation(initialGrade: first.gradePercent)
        }
    }

    /// Called once per VM timer tick (typically 1Hz). Reads the latest speed
    /// reading from the bike, integrates it over the elapsed tick interval,
    /// advances the position cursor, and asks the trainer for the new grade.
    func tick(now: Date) {
        defer { lastTickDate = now }
        guard !isFinished else { return }

        // On the first tick after begin/resume there's no baseline — integrate
        // zero meters this tick so we don't accidentally jump using a stale dt.
        guard let lastTick = lastTickDate else { return }
        let dt = now.timeIntervalSince(lastTick)
        guard dt > 0 else { return }

        // Distance source: prefer cycling-physics "virtual speed" computed
        // from the rider's measured power and the current grade — this gives
        // realistic downhill coasting and uphill drag that the trainer's
        // own speed reading misses (indoor flywheels have negligible
        // momentum vs. an outdoor bike). Fall back to the trainer's reported
        // speed if no power data is available (e.g. a cadence-only sensor).
        let speedMS = virtualSpeedMS() ?? trainerSpeedMS()
        let deltaMeters = max(0, speedMS * dt)
        if deltaMeters > 0 {
            advance(by: deltaMeters)
        }

        if distanceMeters >= route.totalDistanceMeters {
            finish()
            return
        }

        // Push the current grade — TrainerController throttles internally so
        // we can call every tick without flooding the BLE control point.
        Task { [trainerController, currentGradePercent] in
            await trainerController?.setGrade(currentGradePercent)
        }
    }

    /// Called by the VM on pause. Drops the dt baseline so a long-paused
    /// resume tick doesn't integrate the gap as movement.
    func pause() {
        lastTickDate = nil
    }

    /// Called by the VM on resume. The next `tick(now:)` will set the baseline.
    func resume() {
        lastTickDate = nil
    }

    /// End the route. Drops the trainer back to flat so the rider isn't
    /// stuck against the final climb's grade.
    func reset() async {
        finish()
    }

    // MARK: - Private

    /// Compute virtual speed in m/s from the rider's instantaneous power and
    /// the current segment's grade. Nil when power data is unavailable.
    private func virtualSpeedMS() -> Double? {
        guard let power = bikeManager?.latestBikeData?.instantaneousPower else {
            return nil
        }
        // A momentary 0 W reading on a descent is still meaningful (rider
        // coasting), so we DON'T treat power=0 as "no data". Pass it through.
        let weight = settings?.riderWeightKg ?? 75
        return CyclingPhysics.virtualSpeedMS(
            powerWatts: Double(power),
            gradePercent: currentGradePercent,
            riderWeightKg: weight
        )
    }

    private func trainerSpeedMS() -> Double {
        // FTMS reports instantaneousSpeed in km/h (resolution 0.01).
        let kmh = bikeManager?.latestBikeData?.instantaneousSpeed ?? 0
        return max(0, kmh / 3.6)
    }

    private func advance(by meters: Double) {
        guard !routePoints.isEmpty else { return }

        let prevElevation = currentElevation()
        distanceMeters += meters

        // Walk the cursor forward — O(1) amortized since the array is sorted
        // and we never go backwards.
        while currentPointIndex + 1 < routePoints.count
              && routePoints[currentPointIndex + 1].distanceMeters <= distanceMeters {
            currentPointIndex += 1
        }
        currentGradePercent = routePoints[currentPointIndex].gradePercent

        let nowElevation = currentElevation()
        let dz = nowElevation - prevElevation
        if dz > 0 {
            elevationGainMeters += dz
        } else if dz < 0 {
            elevationLossMeters += -dz
        }
    }

    /// Snapshot of the interpolated position at `distanceMeters`. Mirrors the
    /// elevation-interpolation strategy for lat/lon so HealthKit `CLLocation`
    /// samples follow a smooth path between resampled route points.
    func currentPosition() -> RoutePositionSnapshot? {
        guard !routePoints.isEmpty else { return nil }
        let lo = routePoints[currentPointIndex]
        if currentPointIndex + 1 >= routePoints.count {
            return RoutePositionSnapshot(
                distanceMeters: distanceMeters,
                elevationMeters: lo.elevationMeters,
                latitude: lo.latitude,
                longitude: lo.longitude,
                gradePercent: lo.gradePercent
            )
        }
        let hi = routePoints[currentPointIndex + 1]
        let span = max(hi.distanceMeters - lo.distanceMeters, 0.0001)
        let t = max(0, min(1, (distanceMeters - lo.distanceMeters) / span))
        let lat = lo.latitude + (hi.latitude - lo.latitude) * t
        let lon = lo.longitude + (hi.longitude - lo.longitude) * t
        let ele = lo.elevationMeters + (hi.elevationMeters - lo.elevationMeters) * t
        return RoutePositionSnapshot(
            distanceMeters: distanceMeters,
            elevationMeters: ele,
            latitude: lat,
            longitude: lon,
            gradePercent: currentGradePercent
        )
    }

    private func currentElevation() -> Double {
        currentPosition()?.elevationMeters ?? 0
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        distanceMeters = min(distanceMeters, route.totalDistanceMeters)
        Task { [trainerController] in
            await trainerController?.setGrade(0)
        }
    }
}
