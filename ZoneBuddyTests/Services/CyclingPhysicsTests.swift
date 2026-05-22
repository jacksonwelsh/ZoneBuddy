import Testing
import Foundation
@testable import ZoneBuddy

@MainActor
struct CyclingPhysicsTests {

    @Test
    func zeroPowerOnFlatProducesZeroSpeed() {
        let v = CyclingPhysics.virtualSpeedMS(
            powerWatts: 0, gradePercent: 0, riderWeightKg: 75
        )
        #expect(v < 0.1)
    }

    @Test
    func twoHundredWattsOnFlatRoughlyMatchesRealWorld() {
        // 200 W on a flat road at 75 kg rider + ~8 kg bike is roughly
        // 30–34 km/h in standard cycling-calculator outputs. Allow a wide
        // band — what matters is the right order of magnitude.
        let v = CyclingPhysics.virtualSpeedMS(
            powerWatts: 200, gradePercent: 0, riderWeightKg: 75
        )
        let kmh = v * 3.6
        #expect(kmh > 25 && kmh < 40)
    }

    @Test
    func climbingSlowsTheRiderAtSamePower() {
        let flat = CyclingPhysics.virtualSpeedMS(
            powerWatts: 200, gradePercent: 0, riderWeightKg: 75
        )
        let climb = CyclingPhysics.virtualSpeedMS(
            powerWatts: 200, gradePercent: 8, riderWeightKg: 75
        )
        #expect(climb < flat * 0.5)
    }

    @Test
    func descentLetsRiderCoastAtZeroPower() {
        // -8% grade with no input → rider still moves (gravity wins over
        // rolling + drag at some equilibrium speed).
        let v = CyclingPhysics.virtualSpeedMS(
            powerWatts: 0, gradePercent: -8, riderWeightKg: 75
        )
        let kmh = v * 3.6
        #expect(kmh > 20)
    }

    @Test
    func heavierRiderClimbsSlowerAtSamePower() {
        let light = CyclingPhysics.virtualSpeedMS(
            powerWatts: 250, gradePercent: 6, riderWeightKg: 60
        )
        let heavy = CyclingPhysics.virtualSpeedMS(
            powerWatts: 250, gradePercent: 6, riderWeightKg: 90
        )
        #expect(heavy < light)
    }

    @Test
    func heavierRiderDescendsFasterAtZeroPower() {
        // On a descent, gravity helps proportionally to mass — the heavier
        // rider reaches a higher equilibrium coasting speed.
        let light = CyclingPhysics.virtualSpeedMS(
            powerWatts: 0, gradePercent: -6, riderWeightKg: 60
        )
        let heavy = CyclingPhysics.virtualSpeedMS(
            powerWatts: 0, gradePercent: -6, riderWeightKg: 90
        )
        #expect(heavy > light)
    }

    @Test
    func speedIsClampedToPhysicalLimit() {
        // 2000W on a 25% descent should not return 500 km/h.
        let v = CyclingPhysics.virtualSpeedMS(
            powerWatts: 2000, gradePercent: -25, riderWeightKg: 75
        )
        #expect(v <= 30)
    }
}
