import CoreBluetooth
import HealthKit

extension Notification.Name {
    static let watchReceivedPause = Notification.Name("watchReceivedPause")
    static let watchReceivedResume = Notification.Name("watchReceivedResume")
    static let watchReceivedDismiss = Notification.Name("watchReceivedDismiss")
}

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

    /// Current trainer target watts as last published by the iPad over BLE.
    /// `nil` when the iPad is not in ERG mode (or before we've received the first
    /// notify/read). The Watch UI uses this as the baseline when the Crown starts
    /// turning so the absolute target it sends back always matches what the iPad
    /// will apply.
    private(set) var currentTrainerTarget: Int?

    /// Current trainer resistance level as last published by the iPad. Non-nil
    /// means the iPad is in Level mode — the Crown drives this instead of target
    /// watts, so we never kick the trainer back to ERG.
    private(set) var currentTrainerResistance: Int?
    /// Lower bound of the bike's supported resistance range as reported by the iPad.
    /// `nil` when unknown. The Watch UI clamps Crown input to `[min, max]` in Level
    /// mode so the displayed value always matches what the iPad will apply.
    private(set) var trainerResistanceMin: Int?
    /// Upper bound of the bike's supported resistance range.
    private(set) var trainerResistanceMax: Int?

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

    /// Send the Watch's cumulative HR-based active-energy estimate to the iPad.
    /// The iPad consumes the most recent value at workout end to decide whether
    /// to top up Fitness "Total Calories" via a basal-energy delta sample.
    func updateEnergy(_ kcal: Int) {
        centralDelegate?.updateEnergy(kcal)
    }

    /// Send a command from Watch to iPad (pause/resume/end). Byte values come from the
    /// shared `BLECommand` enum so they cannot drift from the iPad side.
    func sendWatchPaused() { centralDelegate?.sendWatchCommand(.pauseWorkout) }
    func sendWatchResumed() { centralDelegate?.sendWatchCommand(.resumeWorkout) }
    func sendWatchEnded() { centralDelegate?.sendWatchCommand(.endWorkout) }

    /// Send a Digital Crown-driven absolute target watts to the host. The Watch
    /// computes the new absolute target locally (baseline + accumulated ticks)
    /// using `currentTrainerTarget`, so the value here is exactly what the iPad
    /// will set on the trainer. Encoded as a 2-byte little-endian `Int16`.
    func sendTrainerTarget(_ watts: Int) {
        centralDelegate?.sendTrainerTarget(watts)
    }

    /// Send a Digital Crown-driven absolute resistance level. Same encoding as the
    /// target channel. Watch UI only calls this when `currentTrainerResistance`
    /// is non-nil — i.e. when the iPad is already in Level mode.
    func sendTrainerResistance(_ level: Int) {
        centralDelegate?.sendTrainerResistance(level)
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
        private var manager: CBCentralManager?
        private var connectedPeripheral: CBPeripheral?
        private var hrCharacteristic: CBCharacteristic?
        private var commandCharacteristic: CBCharacteristic?
        private var watchCommandCharacteristic: CBCharacteristic?
        private var trainerTargetCharacteristic: CBCharacteristic?
        private var trainerResistanceCharacteristic: CBCharacteristic?
        private var watchEnergyCharacteristic: CBCharacteristic?

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
            watchCommandCharacteristic = nil
            trainerTargetCharacteristic = nil
            trainerResistanceCharacteristic = nil
            watchEnergyCharacteristic = nil
            manager = nil
        }

        func updateHeartRate(_ bpm: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = hrCharacteristic else { return }
            let data = Data([UInt8(clamping: bpm)])
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }

        func updateEnergy(_ kcal: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = watchEnergyCharacteristic else { return }
            let clamped = UInt16(clamping: max(0, kcal))
            let payload = withUnsafeBytes(of: clamped.littleEndian) { Data($0) }
            peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
        }

        func sendWatchCommand(_ command: BLECommand) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = watchCommandCharacteristic else { return }
            peripheral.writeValue(Data([command.rawValue]), for: characteristic, type: .withoutResponse)
        }

        func sendTrainerTarget(_ watts: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = trainerTargetCharacteristic else { return }
            let clamped = Int16(clamping: max(0, watts))
            let payload = withUnsafeBytes(of: clamped.littleEndian) { Data($0) }
            peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
        }

        func sendTrainerResistance(_ level: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = trainerResistanceCharacteristic else { return }
            let clamped = Int16(clamping: max(0, level))
            let payload = withUnsafeBytes(of: clamped.littleEndian) { Data($0) }
            peripheral.writeValue(payload, for: characteristic, type: .withoutResponse)
        }

        // MARK: - CBCentralManagerDelegate

        nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
            print("WatchHRBroadcaster: state updated to \(central.state.rawValue)")
            guard central.state == .poweredOn else { return }
            print("WatchHRBroadcaster: scanning for HR receiver service")
            central.scanForPeripherals(
                withServices: [BLEProtocol.serviceUUID],
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
            peripheral.discoverServices([BLEProtocol.serviceUUID])
        }

        nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
            print("WatchHRBroadcaster: failed to connect: \(error?.localizedDescription ?? "unknown")")
            central.scanForPeripherals(
                withServices: [BLEProtocol.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            print("WatchHRBroadcaster: disconnected: \(error?.localizedDescription ?? "clean")")
            Task { @MainActor in
                self.connectedPeripheral = nil
                self.hrCharacteristic = nil
                self.commandCharacteristic = nil
                self.trainerTargetCharacteristic = nil
                self.trainerResistanceCharacteristic = nil
                self.watchEnergyCharacteristic = nil
                // Drop any stale cached values so the Watch UI doesn't show data
                // that may have changed while disconnected.
                WatchHRBroadcaster.shared.currentTrainerTarget = nil
                WatchHRBroadcaster.shared.currentTrainerResistance = nil
                WatchHRBroadcaster.shared.trainerResistanceMin = nil
                WatchHRBroadcaster.shared.trainerResistanceMax = nil
                self.manager?.scanForPeripherals(
                    withServices: [BLEProtocol.serviceUUID],
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
            for service in services where service.uuid == BLEProtocol.serviceUUID {
                peripheral.discoverCharacteristics(
                    [
                        BLEProtocol.hrCharUUID,
                        BLEProtocol.commandCharUUID,
                        BLEProtocol.watchCommandCharUUID,
                        BLEProtocol.trainerTargetCharUUID,
                        BLEProtocol.trainerResistanceCharUUID,
                        BLEProtocol.watchEnergyCharUUID,
                    ],
                    for: service
                )
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
                if characteristic.uuid == BLEProtocol.hrCharUUID {
                    print("WatchHRBroadcaster: found HR characteristic, ready to send")
                    Task { @MainActor in
                        self.hrCharacteristic = characteristic
                    }
                } else if characteristic.uuid == BLEProtocol.commandCharUUID {
                    print("WatchHRBroadcaster: found command characteristic, subscribing + reading")
                    peripheral.setNotifyValue(true, for: characteristic)
                    // Proactive read: if the iPad already has a workout running, this fetches
                    // its JSON so we navigate immediately instead of waiting for the iPad's
                    // didSubscribeTo notification (which can be dropped on a flaky reconnect).
                    peripheral.readValue(for: characteristic)
                    Task { @MainActor in
                        self.commandCharacteristic = characteristic
                    }
                } else if characteristic.uuid == BLEProtocol.watchCommandCharUUID {
                    print("WatchHRBroadcaster: found Watch command characteristic, ready to send")
                    Task { @MainActor in
                        self.watchCommandCharacteristic = characteristic
                    }
                } else if characteristic.uuid == BLEProtocol.trainerTargetCharUUID {
                    print("WatchHRBroadcaster: found trainer-target characteristic, subscribing + reading")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                    Task { @MainActor in
                        self.trainerTargetCharacteristic = characteristic
                    }
                } else if characteristic.uuid == BLEProtocol.trainerResistanceCharUUID {
                    print("WatchHRBroadcaster: found trainer-resistance characteristic, subscribing + reading")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                    Task { @MainActor in
                        self.trainerResistanceCharacteristic = characteristic
                    }
                } else if characteristic.uuid == BLEProtocol.watchEnergyCharUUID {
                    print("WatchHRBroadcaster: found watch-energy characteristic, ready to send")
                    Task { @MainActor in
                        self.watchEnergyCharacteristic = characteristic
                    }
                }
            }
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            if let error {
                print("WatchHRBroadcaster: \(characteristic.uuid) update error: \(error)")
                return
            }
            guard let data = characteristic.value, !data.isEmpty else { return }

            if characteristic.uuid == BLEProtocol.trainerTargetCharUUID {
                guard data.count >= 2 else { return }
                let unsigned = UInt16(data[0]) | (UInt16(data[1]) << 8)
                let value = Int16(bitPattern: unsigned)
                let resolved: Int? = (value == BLEProtocol.trainerTargetNoneSentinel) ? nil : Int(value)
                Task { @MainActor in
                    WatchHRBroadcaster.shared.currentTrainerTarget = resolved
                }
                return
            }

            if characteristic.uuid == BLEProtocol.trainerResistanceCharUUID {
                // Payload: 6 bytes — three LE Int16s: current, min, max.
                guard data.count >= 6 else { return }
                func decode(_ offset: Int) -> Int? {
                    let unsigned = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                    let value = Int16(bitPattern: unsigned)
                    return value == BLEProtocol.trainerResistanceNoneSentinel ? nil : Int(value)
                }
                let current = decode(0)
                let lo = decode(2)
                let hi = decode(4)
                Task { @MainActor in
                    WatchHRBroadcaster.shared.currentTrainerResistance = current
                    WatchHRBroadcaster.shared.trainerResistanceMin = lo
                    WatchHRBroadcaster.shared.trainerResistanceMax = hi
                }
                return
            }

            guard characteristic.uuid == BLEProtocol.commandCharUUID else { return }

            // The iPad uses the same characteristic for two payload shapes: 1-byte command
            // notifications (start/pause/resume/end) and multi-byte read responses carrying
            // the workout JSON. Discriminate by length — using a stateful flag here gets
            // wedged if a read is interrupted, silently dropping every subsequent command.
            Task { @MainActor in
                if data.count > 1 {
                    self.handleWorkoutData(data)
                    return
                }

                guard let command = BLECommand(rawValue: data[0]) else {
                    print("WatchHRBroadcaster: unknown command \(data[0])")
                    return
                }
                switch command {
                case .startWorkout:
                    print("WatchHRBroadcaster: received startWorkout command, reading workout data")
                    peripheral.readValue(for: characteristic)
                case .pauseWorkout:
                    print("WatchHRBroadcaster: received pauseWorkout command")
                    NotificationCenter.default.post(name: .watchReceivedPause, object: nil)
                case .resumeWorkout:
                    print("WatchHRBroadcaster: received resumeWorkout command")
                    NotificationCenter.default.post(name: .watchReceivedResume, object: nil)
                case .endWorkout:
                    print("WatchHRBroadcaster: received endWorkout command")
                    NotificationCenter.default.post(name: .watchReceivedDismiss, object: nil)
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
