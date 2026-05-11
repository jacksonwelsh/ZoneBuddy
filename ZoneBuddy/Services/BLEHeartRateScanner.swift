import CoreBluetooth
import os

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
    /// Lock-protected because the BLE delegate (running on CoreBluetooth's internal queue)
    /// reads it from `peripheralManager(_:didReceiveRead:)` concurrently with MainActor
    /// writes from `sendWorkoutStart` / `sendEndCommand`.
    @ObservationIgnored private let pendingWorkoutData = OSAllocatedUnfairLock<Data?>(initialState: nil)

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
                self?.pendingWorkoutData.withLock { $0 }
            },
            onWatchCommand: { [weak self] command in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch command {
                    case .pauseWorkout: self.watchPausedWorkout = true
                    case .resumeWorkout: self.watchResumedWorkout = true
                    case .endWorkout: self.watchEndedWorkout = true
                    case .startWorkout: break // iPad is the producer, ignore reflected start
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
        pendingWorkoutData.withLock { $0 = nil }
    }

    // MARK: - Workout Commands (iPad → Watch via BLE)

    func sendWorkoutStart(_ transferData: WorkoutTransferData) {
        let encoded = try? JSONEncoder().encode(transferData)
        pendingWorkoutData.withLock { $0 = encoded }
        peripheralDelegate?.sendCommand(.startWorkout)
    }

    func sendPauseCommand() {
        peripheralDelegate?.sendCommand(.pauseWorkout)
    }

    func sendResumeCommand() {
        peripheralDelegate?.sendCommand(.resumeWorkout)
    }

    func sendEndCommand() {
        peripheralDelegate?.sendCommand(.endWorkout)
        pendingWorkoutData.withLock { $0 = nil }
    }

    // MARK: - Peripheral Delegate

    private class PeripheralDelegate: NSObject, CBPeripheralManagerDelegate {
        private var manager: CBPeripheralManager?
        private let onHeartRate: @Sendable (Int) -> Void
        private let getWorkoutData: @Sendable () -> Data?
        private let onWatchCommand: @Sendable (BLECommand) -> Void
        private var commandCharacteristic: CBMutableCharacteristic?

        init(
            onHeartRate: @escaping @Sendable (Int) -> Void,
            getWorkoutData: @escaping @Sendable () -> Data?,
            onWatchCommand: @escaping @Sendable (BLECommand) -> Void
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

        func sendCommand(_ command: BLECommand) {
            guard let manager, let characteristic = commandCharacteristic else {
                print("BLEHeartRateScanner: cannot send command \(command) — not ready")
                return
            }
            let sent = manager.updateValue(Data([command.rawValue]), for: characteristic, onSubscribedCentrals: nil)
            print("BLEHeartRateScanner: sent command \(command), queued: \(sent)")
        }

        // MARK: - CBPeripheralManagerDelegate

        nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            print("BLEHeartRateScanner: state updated to \(peripheral.state.rawValue)")
            guard peripheral.state == .poweredOn else { return }

            let hrCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.hrCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let cmdCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.commandCharUUID,
                properties: [.read, .notify],
                value: nil,
                permissions: .readable
            )

            // Watch writes pause/resume/end commands here
            let watchCmdCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.watchCommandCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let service = CBMutableService(type: BLEProtocol.serviceUUID, primary: true)
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
                CBAdvertisementDataServiceUUIDsKey: [BLEProtocol.serviceUUID],
                CBAdvertisementDataLocalNameKey: BLEProtocol.advertisedLocalName,
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
                if request.characteristic.uuid == BLEProtocol.hrCharUUID {
                    let bpm = Int(data[0])
                    onHeartRate(bpm)
                } else if request.characteristic.uuid == BLEProtocol.watchCommandCharUUID {
                    guard let command = BLECommand(rawValue: data[0]) else {
                        print("BLEHeartRateScanner: unknown Watch command \(data[0])")
                        continue
                    }
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
            if characteristic.uuid == BLEProtocol.commandCharUUID, getWorkoutData() != nil {
                Task { @MainActor in
                    self.sendCommand(.startWorkout)
                }
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            print("BLEHeartRateScanner: central unsubscribed from \(characteristic.uuid)")
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            guard request.characteristic.uuid == BLEProtocol.commandCharUUID else {
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

#if DEBUG
extension BLEHeartRateScanner {
    func debugSimulateInboundHR(_ bpm: Int) {
        latestHeartRate = bpm
    }

    func debugSimulatePauseFromWatch() {
        watchPausedWorkout = true
    }

    func debugSimulateResumeFromWatch() {
        watchResumedWorkout = true
    }

    func debugSimulateEndFromWatch() {
        watchEndedWorkout = true
    }
}
#endif
