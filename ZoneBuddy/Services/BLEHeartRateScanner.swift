import CoreBluetooth

/// Receives heart rate from a Watch over BLE.
/// The iPad/iPhone acts as a CBPeripheral, advertising a custom "HR Receiver"
/// service with a writable characteristic. The Watch connects as a central
/// and writes HR values to it. This reversed architecture is necessary because
/// watchOS does not support CBPeripheralManager.
@Observable
final class BLEHeartRateScanner: HeartRateStreaming {
    private(set) var latestHeartRate: Int?
    private var peripheralDelegate: PeripheralDelegate?

    func startMonitoring(from startDate: Date) {
        guard peripheralDelegate == nil else { return }
        peripheralDelegate = PeripheralDelegate { [weak self] bpm in
            Task { @MainActor [weak self] in
                self?.latestHeartRate = bpm
            }
        }
    }

    func stopMonitoring() {
        peripheralDelegate?.stop()
        peripheralDelegate = nil
        latestHeartRate = nil
    }

    // MARK: - Peripheral Delegate

    private class PeripheralDelegate: NSObject, CBPeripheralManagerDelegate {
        /// Must match WatchHRBroadcaster.CentralDelegate.serviceUUID
        nonisolated(unsafe) private static let serviceUUID = CBUUID(string: "B5E5D4A1-4F2C-4C33-9E01-1A2B3C4D5E6F")
        /// Must match WatchHRBroadcaster.CentralDelegate.hrCharUUID
        nonisolated(unsafe) private static let hrCharUUID = CBUUID(string: "B5E5D4A2-4F2C-4C33-9E01-1A2B3C4D5E6F")

        private var manager: CBPeripheralManager?
        private let onHeartRate: @Sendable (Int) -> Void

        init(onHeartRate: @escaping @Sendable (Int) -> Void) {
            self.onHeartRate = onHeartRate
            super.init()
            manager = CBPeripheralManager(delegate: self, queue: nil)
        }

        func stop() {
            manager?.stopAdvertising()
            manager?.removeAllServices()
            manager = nil
        }

        // MARK: - CBPeripheralManagerDelegate

        nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            guard peripheral.state == .poweredOn else { return }

            let hrCharacteristic = CBMutableCharacteristic(
                type: Self.hrCharUUID,
                properties: [.writeWithoutResponse],
                value: nil,
                permissions: .writeable
            )

            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [hrCharacteristic]
            peripheral.add(service)
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
            if let error {
                print("BLEHeartRateScanner: failed to add service: \(error)")
                return
            }
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "ZoneBuddy",
            ])
        }

        nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            for request in requests {
                guard request.characteristic.uuid == Self.hrCharUUID,
                      let data = request.value,
                      !data.isEmpty else { continue }
                let bpm = Int(data[0])
                onHeartRate(bpm)
            }
        }
    }
}
