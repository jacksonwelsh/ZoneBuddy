#if DEBUG
import Foundation
import FTMSKit

/// Debug-only fake `BikeConnecting` that emits time-varying data driven by
/// `SimulatorFakes.shared.targetPower`. Power, cadence, speed, distance, and
/// energy are smoothed/integrated in a 1Hz loop to mimic real FTMS packets.
@Observable
final class FakeBikeConnectionManager: BikeConnecting {
    static let shared = FakeBikeConnectionManager()

    private(set) var isConnected: Bool = true
    private(set) var connectedBikeName: String? = "Sim Bike (Fake)"
    private(set) var latestBikeData: BikeData? = nil
    private(set) var discoveredDevices: [FTMSDiscoveredDevice] = []
    private(set) var isScanning: Bool = false
    private(set) var accumulatedSamples: [BikeDataSample] = []
    private(set) var hasReceivedNonZeroMetric: Bool = true
    private(set) var isReconnecting: Bool = false

    @ObservationIgnored private var generatorTask: Task<Void, Never>?
    @ObservationIgnored private var smoothedPower: Double = 100
    @ObservationIgnored private var smoothedCadence: Double = 80
    @ObservationIgnored private var totalDistanceMeters: Double = 0
    @ObservationIgnored private var totalEnergyKcal: Double = 0

    private init() {
        // Start emitting immediately so views that read the fake before any
        // `autoConnect(...)` call (e.g. mid-onboarding) still see live data.
        startGenerator()
    }

    func startScanning() {}
    func stopScanning() {}
    func connect(to device: FTMSDiscoveredDevice) {}
    func attemptReconnect() {}

    func disconnect() {
        // Route through SimulatorFakes so the debug-section toggle reflects
        // the new state and a subsequent flip-back actually reconnects.
        // Keeping the generator running lets the tick loop resume cleanly.
        SimulatorFakes.shared.bikeConnected = false
        isConnected = false
        latestBikeData = nil
    }

    func autoConnect(timeout: TimeInterval) {
        SimulatorFakes.shared.bikeConnected = true
        isConnected = true
        connectedBikeName = "Sim Bike (Fake)"
        startGenerator()
    }

    func drainSamples() -> [BikeDataSample] {
        let s = accumulatedSamples
        accumulatedSamples.removeAll()
        return s
    }

    private func startGenerator() {
        generatorTask?.cancel()
        generatorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?.tick()
            }
        }
    }

    private func tick() {
        let fakes = SimulatorFakes.shared

        if !fakes.bikeConnected {
            if isConnected {
                isConnected = false
                latestBikeData = nil
            }
            return
        }
        if !isConnected {
            isConnected = true
            connectedBikeName = "Sim Bike (Fake)"
        }

        let target = Double(max(0, fakes.targetPower))
        // Low-pass toward target with ~5% noise (95% in ~7s at coeff 0.35).
        let noise = Double.random(in: -0.05...0.05) * max(target, 50)
        smoothedPower += (target + noise - smoothedPower) * 0.35
        smoothedPower = max(0, smoothedPower)

        // Cadence: 70 + min(25, target/10) rpm with ±1 rpm jitter.
        let targetCadence = 70 + min(25, target / 10)
        smoothedCadence += (targetCadence - smoothedCadence) * 0.25
        smoothedCadence += Double.random(in: -1...1)
        smoothedCadence = max(0, smoothedCadence)

        // Speed: rough power→speed mapping (km/h).
        let speedKmh = sqrt(max(0, smoothedPower) * 0.7) + Double.random(in: -0.3...0.3)
        let speedClamped = max(0, speedKmh)

        let dt = 1.0
        totalDistanceMeters += speedClamped * (1000.0 / 3600.0) * dt
        // Cycling efficiency ≈ 0.25, so kcal ≈ joules / (4184 × 0.25).
        totalEnergyKcal += smoothedPower * dt / (4184.0 * 0.25)

        let now = Date()
        let data = BikeData(
            instantaneousSpeed: speedClamped,
            instantaneousCadence: smoothedCadence,
            instantaneousPower: Int(smoothedPower),
            timestamp: now
        )
        latestBikeData = data
        accumulatedSamples.append(BikeDataSample(
            timestamp: now,
            power: Int(smoothedPower),
            cadence: smoothedCadence,
            heartRate: nil,
            speed: speedClamped,
            distance: Int(totalDistanceMeters),
            calories: Int(totalEnergyKcal)
        ))
    }
}
#endif
