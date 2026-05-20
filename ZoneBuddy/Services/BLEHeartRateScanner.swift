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
    /// Most recent absolute target watts written by the Watch over BLE. Players
    /// observe via `.onChange` and consume the value, then reset to nil. Pulse
    /// semantics (vs. cumulative total) match the existing pause/resume flags.
    /// The Watch now computes the absolute target locally (baseline + Crown ticks)
    /// using the value the iPad notifies back on `trainerTargetCharUUID`.
    private(set) var watchTrainerTargetWrite: Int?
    /// Most recent absolute resistance level written by the Watch over BLE. Same pulse
    /// semantics as `watchTrainerTargetWrite`. The Watch chooses between writing target
    /// vs. resistance based on which value the iPad most recently published — so it
    /// drives the iPad's active mode rather than kicking it back to ERG.
    private(set) var watchTrainerResistanceWrite: Int?
    /// Cumulative HR-based active-energy estimate (kcal) most recently reported by the Watch
    /// over BLE. Updated whenever the Watch's `HKLiveWorkoutBuilder` posts a new energy
    /// statistic. Consumed at workout finalization to decide whether to top up Fitness's
    /// "Total Calories" via a basal-energy delta sample.
    private(set) var latestWatchEnergyKcal: Int?
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
    func resetWatchTrainerTargetWrite() { watchTrainerTargetWrite = nil }
    func resetWatchTrainerResistanceWrite() { watchTrainerResistanceWrite = nil }
    func resetLatestWatchEnergyKcal() { latestWatchEnergyKcal = nil }

    /// Push the current trainer target watts to subscribed Watches. Pass `nil` when
    /// the host is not in ERG mode (the peripheral encodes `-1` as the "no target"
    /// sentinel so the Watch can distinguish that from a real 0W target).
    func publishTrainerTarget(_ targetWatts: Int?) {
        peripheralDelegate?.publishTrainerTarget(targetWatts)
    }

    /// Push the current resistance level + supported bounds to subscribed Watches.
    /// Pass `current: nil` when the host is not in Level mode; pass `min`/`max: nil`
    /// when the bike's resistance range isn't known. The Watch uses bounds to clamp
    /// Crown input so the value it shows always matches what the host will apply.
    func publishTrainerResistance(current: Int?, min: Int?, max: Int?) {
        peripheralDelegate?.publishTrainerResistance(current: current, min: min, max: max)
    }

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
            },
            onTrainerTargetWrite: { [weak self] target in
                Task { @MainActor [weak self] in
                    self?.watchTrainerTargetWrite = target
                }
            },
            onTrainerResistanceWrite: { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.watchTrainerResistanceWrite = level
                }
            },
            onWatchEnergy: { [weak self] kcal in
                Task { @MainActor [weak self] in
                    self?.latestWatchEnergyKcal = kcal
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
        latestWatchEnergyKcal = nil
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
        private let onTrainerTargetWrite: @Sendable (Int) -> Void
        private let onTrainerResistanceWrite: @Sendable (Int) -> Void
        private let onWatchEnergy: @Sendable (Int) -> Void
        private var commandCharacteristic: CBMutableCharacteristic?
        private var trainerTargetCharacteristic: CBMutableCharacteristic?
        private var trainerResistanceCharacteristic: CBMutableCharacteristic?
        /// Last value we published on `trainerTargetCharUUID`. Used to (a) seed read
        /// responses and (b) re-send to a newly subscribed Watch.
        private let lastPublishedTarget = OSAllocatedUnfairLock<Int16>(initialState: BLEProtocol.trainerTargetNoneSentinel)
        /// Last payload (6 bytes: current, min, max) we published on `trainerResistanceCharUUID`.
        /// Seeded with all sentinels so reads before any publish answer "no data".
        private let lastPublishedResistance: OSAllocatedUnfairLock<Data> = {
            let sentinel = BLEProtocol.trainerResistanceNoneSentinel.littleEndian
            var data = Data()
            withUnsafeBytes(of: sentinel) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: sentinel) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: sentinel) { data.append(contentsOf: $0) }
            return OSAllocatedUnfairLock(initialState: data)
        }()

        init(
            onHeartRate: @escaping @Sendable (Int) -> Void,
            getWorkoutData: @escaping @Sendable () -> Data?,
            onWatchCommand: @escaping @Sendable (BLECommand) -> Void,
            onTrainerTargetWrite: @escaping @Sendable (Int) -> Void,
            onTrainerResistanceWrite: @escaping @Sendable (Int) -> Void,
            onWatchEnergy: @escaping @Sendable (Int) -> Void
        ) {
            self.onHeartRate = onHeartRate
            self.getWorkoutData = getWorkoutData
            self.onWatchCommand = onWatchCommand
            self.onTrainerTargetWrite = onTrainerTargetWrite
            self.onTrainerResistanceWrite = onTrainerResistanceWrite
            self.onWatchEnergy = onWatchEnergy
            super.init()
            print("BLEHeartRateScanner: creating CBPeripheralManager")
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }

        func stop() {
            manager?.stopAdvertising()
            manager?.removeAllServices()
            manager = nil
            commandCharacteristic = nil
            trainerTargetCharacteristic = nil
            trainerResistanceCharacteristic = nil
        }

        /// Encode `targetWatts` as 2-byte LE Int16 and notify subscribed centrals.
        /// `nil` becomes the `-1` "no target" sentinel.
        func publishTrainerTarget(_ targetWatts: Int?) {
            let encoded: Int16
            if let w = targetWatts {
                encoded = Int16(clamping: w)
            } else {
                encoded = BLEProtocol.trainerTargetNoneSentinel
            }
            lastPublishedTarget.withLock { $0 = encoded }
            guard let manager, let characteristic = trainerTargetCharacteristic else { return }
            let payload = withUnsafeBytes(of: encoded.littleEndian) { Data($0) }
            let sent = manager.updateValue(payload, for: characteristic, onSubscribedCentrals: nil)
            print("BLEHeartRateScanner: published trainer target \(encoded)W, queued: \(sent)")
        }

        /// Encode `(current, min, max)` as 6-byte little-endian Int16 triple and notify
        /// subscribed centrals. Each `nil` becomes the `-1` sentinel.
        func publishTrainerResistance(current: Int?, min: Int?, max: Int?) {
            func encode(_ value: Int?) -> Int16 {
                guard let v = value else { return BLEProtocol.trainerResistanceNoneSentinel }
                return Int16(clamping: v)
            }
            let cur = encode(current).littleEndian
            let lo = encode(min).littleEndian
            let hi = encode(max).littleEndian
            var payload = Data()
            withUnsafeBytes(of: cur) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: lo) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: hi) { payload.append(contentsOf: $0) }
            lastPublishedResistance.withLock { $0 = payload }
            guard let manager, let characteristic = trainerResistanceCharacteristic else { return }
            let sent = manager.updateValue(payload, for: characteristic, onSubscribedCentrals: nil)
            print("BLEHeartRateScanner: published trainer resistance current=\(cur) min=\(lo) max=\(hi), queued: \(sent)")
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

            // Bidirectional trainer target: Watch writes absolute target watts (2-byte LE Int16);
            // host pushes current `currentTargetWatts` via notify (and answers reads).
            let trainerTargetCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.trainerTargetCharUUID,
                properties: [.read, .write, .writeWithoutResponse, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )

            // Bidirectional trainer resistance: Watch writes absolute level; host notifies
            // `currentResistanceLevel`. Mirrors the target channel.
            let trainerResistanceCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.trainerResistanceCharUUID,
                properties: [.read, .write, .writeWithoutResponse, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )

            // Watch writes cumulative HR-based active-energy estimate (2-byte LE UInt16, kcal).
            let watchEnergyCharacteristic = CBMutableCharacteristic(
                type: BLEProtocol.watchEnergyCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let service = CBMutableService(type: BLEProtocol.serviceUUID, primary: true)
            service.characteristics = [
                hrCharacteristic,
                cmdCharacteristic,
                watchCmdCharacteristic,
                trainerTargetCharacteristic,
                trainerResistanceCharacteristic,
                watchEnergyCharacteristic,
            ]
            peripheral.add(service)

            Task { @MainActor in
                self.commandCharacteristic = cmdCharacteristic
                self.trainerTargetCharacteristic = trainerTargetCharacteristic
                self.trainerResistanceCharacteristic = trainerResistanceCharacteristic
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
                } else if request.characteristic.uuid == BLEProtocol.trainerTargetCharUUID {
                    guard data.count >= 2 else {
                        print("BLEHeartRateScanner: trainer-target payload too short")
                        continue
                    }
                    let unsigned = UInt16(data[0]) | (UInt16(data[1]) << 8)
                    let target = Int(Int16(bitPattern: unsigned))
                    print("BLEHeartRateScanner: received trainer-target write \(target)W")
                    // The Watch should never write the "no target" sentinel — it only sends
                    // concrete absolute targets. Defensively drop negatives.
                    guard target >= 0 else { continue }
                    onTrainerTargetWrite(target)
                } else if request.characteristic.uuid == BLEProtocol.trainerResistanceCharUUID {
                    guard data.count >= 2 else {
                        print("BLEHeartRateScanner: trainer-resistance payload too short")
                        continue
                    }
                    let unsigned = UInt16(data[0]) | (UInt16(data[1]) << 8)
                    let level = Int(Int16(bitPattern: unsigned))
                    print("BLEHeartRateScanner: received trainer-resistance write \(level)")
                    guard level >= 0 else { continue }
                    onTrainerResistanceWrite(level)
                } else if request.characteristic.uuid == BLEProtocol.watchEnergyCharUUID {
                    guard data.count >= 2 else {
                        print("BLEHeartRateScanner: watch-energy payload too short")
                        continue
                    }
                    let kcal = Int(UInt16(data[0]) | (UInt16(data[1]) << 8))
                    onWatchEnergy(kcal)
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
            // Re-push the last-known trainer target so a freshly subscribed Watch knows
            // the current value without having to issue a read.
            if characteristic.uuid == BLEProtocol.trainerTargetCharUUID {
                let last = lastPublishedTarget.withLock { $0 }
                let payload = withUnsafeBytes(of: last.littleEndian) { Data($0) }
                if let manager, let char = trainerTargetCharacteristic {
                    _ = manager.updateValue(payload, for: char, onSubscribedCentrals: [central])
                }
            }
            if characteristic.uuid == BLEProtocol.trainerResistanceCharUUID {
                let payload = lastPublishedResistance.withLock { $0 }
                if let manager, let char = trainerResistanceCharacteristic {
                    _ = manager.updateValue(payload, for: char, onSubscribedCentrals: [central])
                }
            }
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
            print("BLEHeartRateScanner: central unsubscribed from \(characteristic.uuid)")
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            if request.characteristic.uuid == BLEProtocol.commandCharUUID {
                let data = getWorkoutData() ?? Data()
                if request.offset > data.count {
                    peripheral.respond(to: request, withResult: .invalidOffset)
                } else {
                    request.value = data.subdata(in: request.offset..<data.count)
                    peripheral.respond(to: request, withResult: .success)
                }
                return
            }
            if request.characteristic.uuid == BLEProtocol.trainerTargetCharUUID {
                let last = lastPublishedTarget.withLock { $0 }
                let payload = withUnsafeBytes(of: last.littleEndian) { Data($0) }
                if request.offset > payload.count {
                    peripheral.respond(to: request, withResult: .invalidOffset)
                } else {
                    request.value = payload.subdata(in: request.offset..<payload.count)
                    peripheral.respond(to: request, withResult: .success)
                }
                return
            }
            if request.characteristic.uuid == BLEProtocol.trainerResistanceCharUUID {
                let payload = lastPublishedResistance.withLock { $0 }
                if request.offset > payload.count {
                    peripheral.respond(to: request, withResult: .invalidOffset)
                } else {
                    request.value = payload.subdata(in: request.offset..<payload.count)
                    peripheral.respond(to: request, withResult: .success)
                }
                return
            }
            peripheral.respond(to: request, withResult: .requestNotSupported)
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

    func debugSimulateTrainerTargetFromWatch(_ target: Int) {
        watchTrainerTargetWrite = target
    }
}
#endif
