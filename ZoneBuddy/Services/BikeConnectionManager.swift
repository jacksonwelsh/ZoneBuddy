import Foundation
import Combine
import FTMSKit

protocol BikeConnecting: Observable {
    var isConnected: Bool { get }
    var connectedBikeName: String? { get }
    var latestBikeData: BikeData? { get }
    var discoveredDevices: [FTMSDiscoveredDevice] { get }
    var isScanning: Bool { get }
    var accumulatedSamples: [BikeDataSample] { get }
    /// True once we have observed a packet whose power, cadence, or speed is non-zero.
    /// Resets on every (re)connection.
    var hasReceivedNonZeroMetric: Bool { get }
    /// True while a self-heal disconnect+reconnect cycle is in progress.
    var isReconnecting: Bool { get }
    /// Non-nil while connected. Lets workouts send ERG / resistance commands
    /// to the trainer. A fresh instance is constructed on every connect so
    /// callers must re-issue any ERG targets after a reconnect.
    var trainerController: (any TrainerControlling)? { get }

    func startScanning()
    func stopScanning()
    func connect(to device: FTMSDiscoveredDevice)
    func disconnect()
    func drainSamples() -> [BikeDataSample]
    func autoConnect(timeout: TimeInterval)
    /// Disconnect and reconnect to the most recently used bike. Used to recover from
    /// the "connected but stuck at zero" state.
    func attemptReconnect()
}

@Observable
final class LiveBikeConnectionManager: BikeConnecting {
    static let shared = LiveBikeConnectionManager()

    private(set) var isConnected = false
    private(set) var connectedBikeName: String?
    private(set) var latestBikeData: BikeData?
    private(set) var discoveredDevices: [FTMSDiscoveredDevice] = []
    private(set) var isScanning = false
    private(set) var accumulatedSamples: [BikeDataSample] = []
    private(set) var hasReceivedNonZeroMetric: Bool = false
    private(set) var isReconnecting: Bool = false
    private(set) var trainerController: (any TrainerControlling)?

    /// Lazy so that simply accessing `LiveBikeConnectionManager.shared` (via default-arg
    /// evaluation in views, etc.) does not instantiate `FTMSKit` and trigger the iOS
    /// Bluetooth permission prompt. The prompt only fires when the user reaches the
    /// onboarding Bluetooth step, taps Connect in Settings, or auto-connect runs.
    /// `@ObservationIgnored` keeps the @Observable macro from wrapping a `lazy var`,
    /// which it cannot handle.
    @ObservationIgnored private lazy var ftms = FTMSKit()
    private var connectedBike: FTMSBike?
    private var scanTask: Task<Void, Never>?
    private var dataStreamTask: Task<Void, Never>?
    private var autoHealTask: Task<Void, Never>?
    /// Subscribes to the connected bike's feature characteristic so the
    /// "has ever owned a sim-capable trainer" flag flips as soon as caps
    /// arrive (typically a beat after `connect` resolves).
    private var capabilitiesObserver: AnyCancellable?

    /// Most recent FTMSDiscoveredDevice we connected to. Used by `attemptReconnect()`.
    private var lastConnectedDevice: FTMSDiscoveredDevice?
    /// Wall-clock time of the first packet received on the current connection.
    private var firstPacketDate: Date?
    /// How many auto-heal attempts have run on the current attempt-cycle.
    /// Reset to 0 once we observe a non-zero metric.
    private var autoHealAttempts: Int = 0

    /// Wait this long after the first data packet before deciding the bike is stuck at zero.
    /// The user should be able to start pedaling and see at least one non-zero packet within this window.
    private static let autoHealZeroDataWindow: TimeInterval = 5
    /// Cap how many times we'll auto-heal in a row without ever seeing a non-zero metric.
    /// Past this we stop trying — manual user action required.
    private static let maxAutoHealAttempts: Int = 2

    private init() {}

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredDevices = []

        scanTask?.cancel()
        scanTask = Task {
            do {
                let stream = try ftms.scan()
                for await device in stream {
                    if Task.isCancelled { break }
                    if !discoveredDevices.contains(where: { $0.id == device.id }) {
                        discoveredDevices.append(device)
                    }
                }
            } catch {
                print("FTMS scan error: \(error)")
            }
            isScanning = false
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        ftms.stopScan()
        isScanning = false
    }

    func connect(to device: FTMSDiscoveredDevice) {
        stopScanning()

        Task {
            await establishConnection(to: device, isAutoHeal: false)
        }
    }

    /// Scan for the last-connected bike and auto-connect if found within a timeout.
    func autoConnect(timeout: TimeInterval = 8) {
        guard !isConnected else { return }
        guard let savedID = SettingsManager.shared.lastConnectedBikeID,
              let savedUUID = UUID(uuidString: savedID) else { return }

        isScanning = true
        discoveredDevices = []

        scanTask?.cancel()
        scanTask = Task {
            do {
                let stream = try ftms.scan()
                let deadline = Date().addingTimeInterval(timeout)

                for await device in stream {
                    if Task.isCancelled { break }
                    if !discoveredDevices.contains(where: { $0.id == device.id }) {
                        discoveredDevices.append(device)
                    }
                    if device.id == savedUUID {
                        isScanning = false
                        ftms.stopScan()
                        await establishConnection(to: device, isAutoHeal: false)
                        return
                    }
                    if Date() > deadline { break }
                }
            } catch {
                print("Auto-connect scan error: \(error)")
            }
            isScanning = false
        }
    }

    func disconnect() {
        autoHealTask?.cancel()
        autoHealTask = nil
        dataStreamTask?.cancel()
        dataStreamTask = nil
        capabilitiesObserver?.cancel()
        capabilitiesObserver = nil

        if let bike = connectedBike {
            ftms.disconnect(bike)
        }

        connectedBike = nil
        trainerController = nil
        isConnected = false
        connectedBikeName = nil
        latestBikeData = nil
        hasReceivedNonZeroMetric = false
        firstPacketDate = nil
        autoHealAttempts = 0
        lastConnectedDevice = nil
    }

    /// Tear down the current connection and immediately reconnect to the most recently used bike.
    /// Used to recover from the "connected but stuck at zero" state.
    func attemptReconnect() {
        guard !isReconnecting else { return }
        guard let device = lastConnectedDevice else { return }

        isReconnecting = true
        autoHealTask?.cancel()
        autoHealTask = nil
        dataStreamTask?.cancel()
        dataStreamTask = nil

        Task {
            if let bike = connectedBike {
                ftms.disconnect(bike)
            }
            connectedBike = nil
            trainerController = nil
            isConnected = false
            latestBikeData = nil
            hasReceivedNonZeroMetric = false
            firstPacketDate = nil

            // Brief pause to let the BLE stack settle before reconnecting.
            try? await Task.sleep(for: .milliseconds(500))

            await establishConnection(to: device, isAutoHeal: true)
            isReconnecting = false
        }
    }

    func drainSamples() -> [BikeDataSample] {
        let samples = accumulatedSamples
        accumulatedSamples.removeAll()
        return samples
    }

    func clearSamples() {
        accumulatedSamples.removeAll()
    }

    private func establishConnection(to device: FTMSDiscoveredDevice, isAutoHeal: Bool) async {
        do {
            let bike = try await ftms.connect(to: device)
            connectedBike = bike
            trainerController = LiveTrainerController(bike: bike)
            isConnected = true
            connectedBikeName = bike.name ?? device.name ?? "FTMS Bike"
            lastConnectedDevice = device
            hasReceivedNonZeroMetric = false
            firstPacketDate = nil
            if !isAutoHeal {
                // A user-initiated connect resets the heal-attempt counter.
                autoHealAttempts = 0
            }
            observeSimCapability(on: bike)
            startDataStream(bike: bike)

            let settings = SettingsManager.shared
            settings.lastConnectedBikeID = device.id.uuidString
            settings.lastConnectedBikeName = connectedBikeName
        } catch {
            print("FTMS connect error: \(error)")
            isConnected = false
            connectedBikeName = nil
        }
    }

    private func startDataStream(bike: FTMSBike) {
        dataStreamTask?.cancel()
        dataStreamTask = Task {
            for await data in bike.bikeDataStream {
                if Task.isCancelled { break }
                latestBikeData = data
                accumulatedSamples.append(BikeDataSample(
                    timestamp: data.timestamp,
                    power: data.instantaneousPower,
                    cadence: data.instantaneousCadence,
                    heartRate: data.heartRate,
                    speed: data.instantaneousSpeed,
                    distance: data.totalDistance,
                    calories: data.totalEnergy
                ))

                if Self.hasNonZeroPedalingMetric(data) {
                    if !hasReceivedNonZeroMetric {
                        hasReceivedNonZeroMetric = true
                    }
                    autoHealAttempts = 0
                    autoHealTask?.cancel()
                    autoHealTask = nil
                } else if firstPacketDate == nil {
                    firstPacketDate = Date()
                    scheduleAutoHealCheck()
                }
            }

            // Stream ended — bike disconnected
            isConnected = false
            connectedBikeName = nil
            connectedBike = nil
            trainerController = nil
            latestBikeData = nil
            hasReceivedNonZeroMetric = false
            firstPacketDate = nil
            autoHealTask?.cancel()
            autoHealTask = nil
        }
    }

    /// Watches the bike's capabilities publisher until we see Indoor Bike
    /// Simulation support, then sets the sticky settings flag and tears the
    /// subscription down. We never clear the flag — "previously owned a
    /// sim-capable trainer" is the contract that gates Route Ride UI.
    private func observeSimCapability(on bike: FTMSBike) {
        capabilitiesObserver?.cancel()
        if SettingsManager.shared.hasConnectedSimCapableTrainer {
            capabilitiesObserver = nil
            return
        }
        capabilitiesObserver = bike.capabilitiesPublisher
            .compactMap { $0 }
            .filter { $0.simulationParamsSupported }
            .first()
            .sink { [weak self] _ in
                SettingsManager.shared.hasConnectedSimCapableTrainer = true
                self?.capabilitiesObserver = nil
            }
    }

    /// "Pedaling" signal: power, cadence, or speed > 0. Heart rate is excluded since it can come
    /// from a chest strap independent of whether the bike is reporting real metrics.
    private static func hasNonZeroPedalingMetric(_ data: BikeData) -> Bool {
        if let power = data.instantaneousPower, power > 0 { return true }
        if let cadence = data.instantaneousCadence, cadence > 0 { return true }
        if let speed = data.instantaneousSpeed, speed > 0 { return true }
        return false
    }

    private func scheduleAutoHealCheck() {
        autoHealTask?.cancel()
        autoHealTask = Task {
            try? await Task.sleep(for: .seconds(Self.autoHealZeroDataWindow))
            if Task.isCancelled { return }
            guard isConnected,
                  !hasReceivedNonZeroMetric,
                  !isReconnecting,
                  autoHealAttempts < Self.maxAutoHealAttempts else { return }
            autoHealAttempts += 1
            attemptReconnect()
        }
    }
}
