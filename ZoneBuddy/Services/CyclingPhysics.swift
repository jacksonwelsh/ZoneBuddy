import Foundation

/// Cycling-physics helpers for the "virtual speed" computation used in
/// Route Ride mode — given the rider's measured power and the road grade,
/// derive how fast they'd actually be moving outdoors.
///
/// We model three opposing forces (rolling resistance, gravity along the
/// slope, aerodynamic drag) and solve the resulting cubic for v:
///
///   P_rider = (Crr·m·g + m·g·sin(θ) + 0.5·Cw·v²) · v
///
/// θ = atan(grade/100). On a downhill `sin(θ) < 0`, so the gravity term
/// becomes negative and v can be positive even with P = 0 — the rider
/// coasts down the hill. This is the bit that the trainer's reported
/// speed misses.
enum CyclingPhysics {
    /// Bike + accessories. Real cycling-power calculators (Strava, Zwift)
    /// add the system mass to rider mass before the gravity term — without
    /// this, a 75 kg rider feels lighter than they should on every climb.
    static let bikeMassKg: Double = 8.0
    static let gravity: Double = 9.80665
    static let defaultCrr: Double = 0.004
    static let defaultCw: Double = 0.51

    /// Compute the steady-state ground speed (m/s) for the given inputs.
    /// Returns 0 when the cubic has no positive root (e.g. rider not
    /// pedaling on a flat or uphill).
    static func virtualSpeedMS(
        powerWatts: Double,
        gradePercent: Double,
        riderWeightKg: Double,
        crr: Double = defaultCrr,
        cw: Double = defaultCw
    ) -> Double {
        let m = max(riderWeightKg, 30) + bikeMassKg
        let theta = atan(gradePercent / 100)
        let a = 0.5 * cw                                // v³ coefficient
        let b = crr * m * gravity + m * gravity * sin(theta) // v coefficient
        let c = -max(0, powerWatts)                     // constant term

        // f(v)  = a v³ + b v + c
        // f'(v) = 3 a v² + b
        // Initial guess: coasting baseline on a steep descent (where b < 0)
        // is sqrt(-b/a). Elsewhere start from a linear approximation.
        var v: Double
        if b < 0 {
            v = sqrt(-b / a)
        } else {
            // Linear approx (ignore drag): v ≈ P/b. Clamp away from 0
            // so the first Newton step has somewhere to move.
            v = max(0.5, -c / max(b, 1e-3))
        }

        for _ in 0..<25 {
            let f = a * v * v * v + b * v + c
            let fp = 3 * a * v * v + b
            guard abs(fp) > 1e-9 else { break }
            let dv = f / fp
            v -= dv
            if v < 0 { v = 0 }
            if abs(dv) < 1e-4 { break }
        }

        // Sanity clamp — a 1500 W spike on a -20% descent shouldn't yield
        // 200 km/h; cap at 30 m/s (108 km/h).
        return min(max(v, 0), 30)
    }
}
