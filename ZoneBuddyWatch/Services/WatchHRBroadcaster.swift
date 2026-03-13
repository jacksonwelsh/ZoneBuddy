import CoreBluetooth

/// Sends heart rate from the Watch to a nearby iPad/iPhone via BLE.
/// The Watch acts as a CBCentral, connecting to the iPad which advertises
/// a custom "HR Receiver" service. This is necessary because watchOS does
/// not support CBPeripheralManager.
@Observable
final class WatchHRBroadcaster {
    private var centralDelegate: CentralDelegate?

    func start() {
        guard centralDelegate == nil else { return }
        centralDelegate = CentralDelegate()
    }

    func stop() {
        centralDelegate?.stop()
        centralDelegate = nil
    }

    func updateHeartRate(_ bpm: Int) {
        centralDelegate?.updateHeartRate(bpm)
    }

    // MARK: - Central Delegate

    private class CentralDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        /// Custom service UUID for ZoneBuddy HR relay.
        nonisolated(unsafe) static let serviceUUID = CBUUID(string: "B5E5D4A1-4F2C-4C33-9E01-1A2B3C4D5E6F")
        /// Writable characteristic where the Watch sends HR values.
        nonisolated(unsafe) static let hrCharUUID = CBUUID(string: "B5E5D4A2-4F2C-4C33-9E01-1A2B3C4D5E6F")

        private var manager: CBCentralManager?
        private var connectedPeripheral: CBPeripheral?
        private var hrCharacteristic: CBCharacteristic?

        override init() {
            super.init()
            manager = CBCentralManager(delegate: self, queue: nil)
        }

        func stop() {
            manager?.stopScan()
            if let peripheral = connectedPeripheral {
                manager?.cancelPeripheralConnection(peripheral)
            }
            connectedPeripheral = nil
            hrCharacteristic = nil
            manager = nil
        }

        func updateHeartRate(_ bpm: Int) {
            guard let peripheral = connectedPeripheral,
                  let characteristic = hrCharacteristic else { return }
            let data = Data([UInt8(clamping: bpm)])
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }

        // MARK: - CBCentralManagerDelegate

        nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
            guard central.state == .poweredOn else { return }
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
            central.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            Task { @MainActor in
                self.connectedPeripheral = peripheral
            }
        }

        nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            peripheral.discoverServices([Self.serviceUUID])
        }

        nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            Task { @MainActor in
                self.connectedPeripheral = nil
                self.hrCharacteristic = nil
                // Resume scanning
                self.manager?.scanForPeripherals(
                    withServices: [Self.serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }

        // MARK: - CBPeripheralDelegate

        nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard let services = peripheral.services else { return }
            for service in services where service.uuid == Self.serviceUUID {
                peripheral.discoverCharacteristics([Self.hrCharUUID], for: service)
            }
        }

        nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics where characteristic.uuid == Self.hrCharUUID {
                Task { @MainActor in
                    self.hrCharacteristic = characteristic
                }
            }
        }
    }
}
