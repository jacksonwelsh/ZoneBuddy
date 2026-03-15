import CoreBluetooth
import HealthKit

/// Sends heart rate from the Watch to a nearby iPad via BLE.
///
/// Starts at app launch and runs independently of workouts:
/// - Monitors HR passively from HealthKit
/// - Scans for an iPad advertising the ZoneBuddy HR receiver service
/// - When connected, writes HR values to the iPad's writable characteristic
/// - Subscribes to workout command notifications from the iPad
///
/// When a workout is active, call `updateHeartRate(_:)` to feed it the
/// workout's higher-frequency HR data instead of the passive query.
@Observable
final class WatchHRBroadcaster {
    static let shared = WatchHRBroadcaster()

    private var centralDelegate: CentralDelegate?
    private let healthStore = HKHealthStore()
    private var hrQuery: HKAnchoredObjectQuery?

    private init() {}

    func start() {
        guard centralDelegate == nil else { return }
        print("WatchHRBroadcaster: starting")
        centralDelegate = CentralDelegate()
        startPassiveHRMonitoring()
    }

    func stop() {
        stopPassiveHRMonitoring()
        centralDelegate?.stop()
        centralDelegate = nil
    }

    /// Call from an active workout to send higher-frequency HR updates.
    func updateHeartRate(_ bpm: Int) {
        centralDelegate?.updateHeartRate(bpm)
    }

    // MARK: - Passive HR Monitoring

    private func startPassiveHRMonitoring() {
        stopPassiveHRMonitoring()

        guard HKHealthStore.isHealthDataAvailable() else { return }

        let hrType = HKQuantityType(.heartRate)

        Task {
            do {
                try await healthStore.requestAuthorization(toShare: [], read: [hrType])
            } catch {
                print("WatchHRBroadcaster: HR auth error: \(error)")
                return
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: Date(),
                end: nil,
                options: .strictStartDate
            )

            let query = HKAnchoredObjectQuery(
                type: hrType,
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, _, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.processHRSamples(samples)
                }
            }

            query.updateHandler = { [weak self] _, samples, _, _, _ in
                guard let self else { return }
                Task { @MainActor in
                    self.processHRSamples(samples)
                }
            }

            hrQuery = query
            healthStore.execute(query)
        }
    }

    private func stopPassiveHRMonitoring() {
        if let hrQuery {
            healthStore.stop(hrQuery)
        }
        hrQuery = nil
    }

    private func processHRSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }

        let bpm = Int(latest.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in
            self.centralDelegate?.updateHeartRate(bpm)
        }
    }

    // MARK: - Central Delegate

    private class CentralDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        nonisolated(unsafe) static let serviceUUID = CBUUID(string: "B5E5D4A1-4F2C-4C33-9E01-1A2B3C4D5E6F")
        nonisolated(unsafe) static let hrCharUUID = CBUUID(string: "B5E5D4A2-4F2C-4C33-9E01-1A2B3C4D5E6F")
        nonisolated(unsafe) static let commandCharUUID = CBUUID(string: "B5E5D4A3-4F2C-4C33-9E01-1A2B3C4D5E6F")

        private var manager: CBCentralManager?
        private var connectedPeripheral: CBPeripheral?
        private var hrCharacteristic: CBCharacteristic?
        private var commandCharacteristic: CBCharacteristic?
        /// Set to true after receiving a startWorkout notification, cleared after the read completes.
        private var awaitingWorkoutRead = false

        override init() {
            super.init()
            print("WatchHRBroadcaster: creating CBCentralManager")
            manager = CBCentralManager(delegate: self, queue: nil)
        }

        func stop() {
            manager?.stopScan()
            if let peripheral = connectedPeripheral {
                manager?.cancelPeripheralConnection(peripheral)
            }
            connectedPeripheral = nil
            hrCharacteristic = nil
            commandCharacteristic = nil
            manager = nil
        }

        func updateHeartRate(_ bpm: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = hrCharacteristic else { return }
            let data = Data([UInt8(clamping: bpm)])
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }

        // MARK: - CBCentralManagerDelegate

        nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
            print("WatchHRBroadcaster: state updated to \(central.state.rawValue)")
            guard central.state == .poweredOn else { return }
            print("WatchHRBroadcaster: scanning for HR receiver service")
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
            print("WatchHRBroadcaster: discovered peripheral \(peripheral.name ?? "unknown")")
            central.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            Task { @MainActor in
                self.connectedPeripheral = peripheral
            }
        }

        nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            print("WatchHRBroadcaster: connected to \(peripheral.name ?? "unknown")")
            peripheral.discoverServices([Self.serviceUUID])
        }

        nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            print("WatchHRBroadcaster: failed to connect: \(error?.localizedDescription ?? "unknown")")
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            print("WatchHRBroadcaster: disconnected: \(error?.localizedDescription ?? "clean")")
            Task { @MainActor in
                self.connectedPeripheral = nil
                self.hrCharacteristic = nil
                self.commandCharacteristic = nil
                self.manager?.scanForPeripherals(
                    withServices: [Self.serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }

        // MARK: - CBPeripheralDelegate

        nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            if let error {
                print("WatchHRBroadcaster: service discovery error: \(error)")
                return
            }
            guard let services = peripheral.services else { return }
            print("WatchHRBroadcaster: discovered \(services.count) service(s)")
            for service in services where service.uuid == Self.serviceUUID {
                peripheral.discoverCharacteristics([Self.hrCharUUID, Self.commandCharUUID], for: service)
            }
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            if let error {
                print("WatchHRBroadcaster: characteristic discovery error: \(error)")
                return
            }
            guard let characteristics = service.characteristics else { return }
            print("WatchHRBroadcaster: discovered \(characteristics.count) characteristic(s)")
            for characteristic in characteristics {
                if characteristic.uuid == Self.hrCharUUID {
                    print("WatchHRBroadcaster: found HR characteristic, ready to send")
                    Task { @MainActor in
                        self.hrCharacteristic = characteristic
                    }
                } else if characteristic.uuid == Self.commandCharUUID {
                    print("WatchHRBroadcaster: found command characteristic, subscribing")
                    peripheral.setNotifyValue(true, for: characteristic)
                    Task { @MainActor in
                        self.commandCharacteristic = characteristic
                    }
                }
            }
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            guard characteristic.uuid == Self.commandCharUUID else { return }
            if let error {
                print("WatchHRBroadcaster: command characteristic error: \(error)")
                return
            }
            guard let data = characteristic.value, !data.isEmpty else { return }

            Task { @MainActor in
                if self.awaitingWorkoutRead {
                    // This is a read response containing workout JSON
                    self.awaitingWorkoutRead = false
                    self.handleWorkoutData(data)
                    return
                }

                let command = data[0]
                switch command {
                case 0x01: // startWorkout — read characteristic for full workout data
                    print("WatchHRBroadcaster: received startWorkout command, reading workout data")
                    self.awaitingWorkoutRead = true
                    peripheral.readValue(for: characteristic)
                case 0x02: // pauseWorkout
                    print("WatchHRBroadcaster: received pauseWorkout command")
                    WatchNavigationManager.shared.shouldPauseWorkout = true
                case 0x03: // resumeWorkout
                    print("WatchHRBroadcaster: received resumeWorkout command")
                    WatchNavigationManager.shared.shouldResumeWorkout = true
                case 0x04: // endWorkout
                    print("WatchHRBroadcaster: received endWorkout command")
                    WatchNavigationManager.shared.shouldDismissWorkout = true
                default:
                    print("WatchHRBroadcaster: unknown command \(command)")
                }
            }
        }

        private func handleWorkoutData(_ data: Data) {
            guard let workout = try? JSONDecoder().decode(WorkoutTransferData.self, from: data) else {
                print("WatchHRBroadcaster: failed to decode workout data (\(data.count) bytes)")
                return
            }
            print("WatchHRBroadcaster: decoded workout '\(workout.name)' with \(workout.intervals.count) intervals")
            guard !WatchNavigationManager.shared.shouldStartWorkout else { return }
            WatchNavigationManager.shared.pendingWorkout = workout
            WatchNavigationManager.shared.shouldStartWorkout = true
            WatchConnectivityManager.shared.stopPolling()
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
            if let error {
                print("WatchHRBroadcaster: write error: \(error)")
            }
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            if let error {
                print("WatchHRBroadcaster: notification state error for \(characteristic.uuid): \(error)")
            } else {
                print("WatchHRBroadcaster: notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
            }
        }
    }
}
