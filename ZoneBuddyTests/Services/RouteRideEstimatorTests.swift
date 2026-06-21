import Testing
import Foundation
@testable import ZoneBuddy

@MainActor
struct RouteRideEstimatorTests {

    /// Build evenly-spaced points at a constant grade over `distance` metres.
    private func makePoints(distance: Double, grade: Double, step: Double = 5) -> [RoutePoint] {
        var pts: [RoutePoint] = []
        var d = 0.0
        while d <= distance {
            pts.append(RoutePoint(
                distanceMeters: d,
                elevationMeters: d * (grade / 100),
                gradePercent: grade,
                latitude: 0,
                longitude: 0
            ))
            d += step
        }
        return pts
    }

    @Test
    func emptyAndSinglePointReturnZero() {
        #expect(RouteRideEstimator.estimatedSeconds(points: [], ftp: 200, riderWeightKg: 75) == 0)
        let single = [RoutePoint(distanceMeters: 0, elevationMeters: 0, gradePercent: 0, latitude: 0, longitude: 0)]
        #expect(RouteRideEstimator.estimatedSeconds(points: single, ftp: 200, riderWeightKg: 75) == 0)
    }

    @Test
    func flatRouteMatchesVirtualSpeed() {
        let distance = 10_000.0
        let ftp = 200
        let weight = 75.0
        let points = makePoints(distance: distance, grade: 0)

        let estimate = RouteRideEstimator.estimatedSeconds(points: points, ftp: ftp, riderWeightKg: weight)

        // On the flat the whole route rides at one steady speed, so the
        // estimate should equal distance / that speed within rounding.
        let power = Double(ftp) * RouteRideEstimator.assumedPowerFraction
        let speed = CyclingPhysics.virtualSpeedMS(powerWatts: power, gradePercent: 0, riderWeightKg: weight)
        let expected = distance / speed
        #expect(abs(estimate - expected) < expected * 0.02)
    }

    @Test
    func climbTakesLongerThanFlat() {
        let distance = 5_000.0
        let flat = RouteRideEstimator.estimatedSeconds(
            points: makePoints(distance: distance, grade: 0), ftp: 200, riderWeightKg: 75
        )
        let climb = RouteRideEstimator.estimatedSeconds(
            points: makePoints(distance: distance, grade: 8), ftp: 200, riderWeightKg: 75
        )
        #expect(climb > flat)
    }
}
