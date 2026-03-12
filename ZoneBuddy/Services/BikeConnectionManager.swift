import Foundation
import FTMSKit

protocol BikeConnecting: Observable {
    var isConnected: Bool { get }
    var connectedBikeName: String? { get }
    var latestBikeData: BikeData? { get }
    var discoveredDevices: [FTMSDiscoveredDevice] { get }
    var isScanning: Bool { get }
    var accumulatedSamples: [BikeDataSample] { get }

    func startScanning()
    func stopScanning()
    func connect(to device: FTMSDiscoveredDevice)
    func disconnect()
    func drainSamples() -> [BikeDataSample]
    func autoConnect(timeout: TimeInterval)
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

    private let ftms = FTMSKit()
    private var connectedBike: FTMSBike?
    private var scanTask: Task<Void, Never>?
    private var dataStreamTask: Task<Void, Never>?

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
            do {
                let bike = try await ftms.connect(to: device)
                connectedBike = bike
                isConnected = true
                connectedBikeName = bike.name ?? device.name ?? "FTMS Bike"
                startDataStream(bike: bike)

                // Remember this bike for auto-reconnect
                let settings = SettingsManager.shared
                settings.lastConnectedBikeID = device.id.uuidString
                settings.lastConnectedBikeName = connectedBikeName
            } catch {
                print("FTMS connect error: \(error)")
                isConnected = false
                connectedBikeName = nil
            }
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
                        // Found our saved bike — connect
                        isScanning = false
                        ftms.stopScan()
                        do {
                            let bike = try await ftms.connect(to: device)
                            connectedBike = bike
                            isConnected = true
                            connectedBikeName = bike.name ?? device.name ?? "FTMS Bike"
                            startDataStream(bike: bike)
                        } catch {
                            print("Auto-connect error: \(error)")
                        }
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
        dataStreamTask?.cancel()
        dataStreamTask = nil

        if let bike = connectedBike {
            ftms.disconnect(bike)
        }

        connectedBike = nil
        isConnected = false
        connectedBikeName = nil
        latestBikeData = nil
    }

    func drainSamples() -> [BikeDataSample] {
        let samples = accumulatedSamples
        accumulatedSamples.removeAll()
        return samples
    }

    func clearSamples() {
        accumulatedSamples.removeAll()
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
            }

            // Stream ended — bike disconnected
            isConnected = false
            connectedBikeName = nil
            connectedBike = nil
            latestBikeData = nil
        }
    }
}
