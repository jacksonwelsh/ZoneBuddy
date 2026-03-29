import CoreBluetooth

/// Receives heart rate from a Watch over BLE and sends workout commands.
/// The iPad/iPhone acts as a CBPeripheral, advertising a custom service.
/// The Watch connects as a central, writes HR values, and subscribes to
/// workout command notifications. This reversed architecture is necessary
/// because watchOS does not support CBPeripheralManager.
@Observable
final class BLEHeartRateScanner: HeartRateStreaming {
    static let shared = BLEHeartRateScanner()

    private(set) var latestHeartRate: Int?
    private(set) var watchPausedWorkout = false
    private(set) var watchResumedWorkout = false
    private(set) var watchEndedWorkout = false
    private var peripheralDelegate: PeripheralDelegate?

    /// Workout JSON the Watch reads after receiving a start notification.
    nonisolated(unsafe) private var pendingWorkoutData: Data?

    private init() {}

    func resetWatchPausedWorkout() { watchPausedWorkout = false }
    func resetWatchResumedWorkout() { watchResumedWorkout = false }
    func resetWatchEndedWorkout() { watchEndedWorkout = false }

    func startMonitoring(from startDate: Date) {
        guard peripheralDelegate == nil else { return }
        print("BLEHeartRateScanner: startMonitoring called")
        peripheralDelegate = PeripheralDelegate(
            onHeartRate: { [weak self] bpm in
                Task { @MainActor [weak self] in
                    self?.latestHeartRate = bpm
                }
            },
            getWorkoutData: { [weak self] in
                self?.pendingWorkoutData
            },
            onWatchCommand: { [weak self] command in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch command {
                    case BLECommand.pauseWorkout:
                        self.watchPausedWorkout = true
                    case BLECommand.resumeWorkout:
                        self.watchResumedWorkout = true
                    case BLECommand.endWorkout:
                        self.watchEndedWorkout = true
                    default:
                        break
                    }
                }
            }
        )
    }

    func stopMonitoring() {
        // Clear HR but keep the peripheral alive so workout commands can still be sent.
        latestHeartRate = nil
    }

    func stopPeripheral() {
        peripheralDelegate?.stop()
        peripheralDelegate = nil
        latestHeartRate = nil
        pendingWorkoutData = nil
    }

    // MARK: - Workout Commands (iPad → Watch via BLE)

    func sendWorkoutStart(_ transferData: WorkoutTransferData) {
        pendingWorkoutData = try? JSONEncoder().encode(transferData)
        peripheralDelegate?.sendCommand(BLECommand.startWorkout)
    }

    func sendPauseCommand() {
        peripheralDelegate?.sendCommand(BLECommand.pauseWorkout)
    }

    func sendResumeCommand() {
        peripheralDelegate?.sendCommand(BLECommand.resumeWorkout)
    }

    func sendEndCommand() {
        peripheralDelegate?.sendCommand(BLECommand.endWorkout)
        pendingWorkoutData = nil
    }

    // MARK: - Peripheral Delegate

    private class PeripheralDelegate: NSObject, CBPeripheralManagerDelegate {
        /// Must match WatchHRBroadcaster UUIDs
        nonisolated(unsafe) private static let serviceUUID = CBUUID(string: "B5E5D4A1-4F2C-4C33-9E01-1A2B3C4D5E6F")
        nonisolated(unsafe) private static let hrCharUUID = CBUUID(string: "B5E5D4A2-4F2C-4C33-9E01-1A2B3C4D5E6F")
        nonisolated(unsafe) private static let commandCharUUID = CBUUID(string: "B5E5D4A3-4F2C-4C33-9E01-1A2B3C4D5E6F")
        /// Watch → iPad command channel (Watch writes here to send pause/resume/end)
        nonisolated(unsafe) private static let watchCommandCharUUID = CBUUID(string: "B5E5D4A4-4F2C-4C33-9E01-1A2B3C4D5E6F")

        private var manager: CBPeripheralManager?
        private let onHeartRate: @Sendable (Int) -> Void
        private let getWorkoutData: @Sendable () -> Data?
        private let onWatchCommand: @Sendable (UInt8) -> Void
        private var commandCharacteristic: CBMutableCharacteristic?

        init(
            onHeartRate: @escaping @Sendable (Int) -> Void,
            getWorkoutData: @escaping @Sendable () -> Data?,
            onWatchCommand: @escaping @Sendable (UInt8) -> Void
        ) {
            self.onHeartRate = onHeartRate
            self.getWorkoutData = getWorkoutData
            self.onWatchCommand = onWatchCommand
            super.init()
            print("BLEHeartRateScanner: creating CBPeripheralManager")
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }

        func stop() {
            manager?.stopAdvertising()
            manager?.removeAllServices()
            manager = nil
            commandCharacteristic = nil
        }

        func sendCommand(_ command: UInt8) {
            guard let manager, let characteristic = commandCharacteristic else {
                print("BLEHeartRateScanner: cannot send command \(command) — not ready")
                return
            }
            let sent = manager.updateValue(Data([command]), for: characteristic, onSubscribedCentrals: nil)
            print("BLEHeartRateScanner: sent command \(command), queued: \(sent)")
        }

        // MARK: - CBPeripheralManagerDelegate

        nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            print("BLEHeartRateScanner: state updated to \(peripheral.state.rawValue)")
            guard peripheral.state == .poweredOn else { return }

            let hrCharacteristic = CBMutableCharacteristic(
                type: Self.hrCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let cmdCharacteristic = CBMutableCharacteristic(
                type: Self.commandCharUUID,
                properties: [.read, .notify],
                value: nil,
                permissions: .readable
            )

            // Watch writes pause/resume/end commands here
            let watchCmdCharacteristic = CBMutableCharacteristic(
                type: Self.watchCommandCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [hrCharacteristic, cmdCharacteristic, watchCmdCharacteristic]
            peripheral.add(service)

            Task { @MainActor in
                self.commandCharacteristic = cmdCharacteristic
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            if let error {
                print("BLEHeartRateScanner: failed to add service: \(error)")
                return
            }
            print("BLEHeartRateScanner: service added, starting advertising")
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "ZoneBuddy",
            ])
        }

        nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
            if let error {
                print("BLEHeartRateScanner: advertising failed: \(error)")
            } else {
                print("BLEHeartRateScanner: now advertising")
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            for request in requests {
                guard let data = request.value, !data.isEmpty else { continue }
                if request.characteristic.uuid == Self.hrCharUUID {
                    let bpm = Int(data[0])
                    onHeartRate(bpm)
                } else if request.characteristic.uuid == Self.watchCommandCharUUID {
                    let command = data[0]
                    print("BLEHeartRateScanner: received Watch command \(command)")
                    onWatchCommand(command)
                }
            }
            if let first = requests.first {
                peripheral.respond(to: first, withResult: .success)
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
            print("BLEHeartRateScanner: central subscribed to \(characteristic.uuid)")
            // If we have a pending workout, notify the new subscriber
            if characteristic.uuid == Self.commandCharUUID, getWorkoutData() != nil {
                Task { @MainActor in
                    self.sendCommand(BLECommand.startWorkout)
                }
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            print("BLEHeartRateScanner: central unsubscribed from \(characteristic.uuid)")
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            guard request.characteristic.uuid == Self.commandCharUUID else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                return
            }
            let data = getWorkoutData() ?? Data()
            if request.offset > data.count {
                peripheral.respond(to: request, withResult: .invalidOffset)
            } else {
                request.value = data.subdata(in: request.offset..<data.count)
                peripheral.respond(to: request, withResult: .success)
            }
        }
    }
}

/// Command bytes sent over BLE between iPad and Watch.
enum BLECommand {
    static let startWorkout: UInt8 = 0x01
    static let pauseWorkout: UInt8 = 0x02
    static let resumeWorkout: UInt8 = 0x03
    static let endWorkout: UInt8 = 0x04
}
