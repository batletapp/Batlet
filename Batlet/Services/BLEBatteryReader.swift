import Foundation
import CoreBluetooth

/// Best-effort reader for the standard GATT Battery Service (0x180F / characteristic 0x2A19),
/// used by many generic (non-Apple) earbuds and BLE peripherals. It only inspects peripherals
/// that macOS already reports as connected, then briefly connects to read the level.
///
/// This is inherently best-effort: many earbuds only expose the battery service to the phone
/// they are paired with, so they may not appear here.
final class BLEBatteryReader: NSObject, ObservableObject {

    var onDevicesChanged: (([Device]) -> Void)?

    private let batteryService = CBUUID(string: "180F")
    private let batteryCharacteristic = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private let queue = DispatchQueue(label: "com.batlet.gatt-reader")
    private var connecting: Set<UUID> = []
    private var results: [UUID: Device] = [:]
    private var pollTimer: DispatchSourceTimer?
    // Hold strong references while connected (CoreBluetooth won't retain them for us).
    private var active: [UUID: CBPeripheral] = [:]

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: queue,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func refresh() {
        queue.async { [weak self] in self?.scanConnected() }
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 60)
        timer.setEventHandler { [weak self] in self?.scanConnected() }
        timer.resume()
        pollTimer = timer
    }

    private func scanConnected() {
        guard let central, central.state == .poweredOn else { return }
        let peripherals = central.retrieveConnectedPeripherals(withServices: [batteryService])
        for peripheral in peripherals where !connecting.contains(peripheral.identifier) {
            connecting.insert(peripheral.identifier)
            active[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    private func publish() {
        let devices = Array(results.values)
        DispatchQueue.main.async { [weak self] in
            self?.onDevicesChanged?(devices)
        }
    }

    private func cleanup(_ peripheral: CBPeripheral) {
        connecting.remove(peripheral.identifier)
        active[peripheral.identifier] = nil
        if results.removeValue(forKey: peripheral.identifier) != nil {
            publish()
        }
    }
}

extension BLEBatteryReader: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startPolling()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cleanup(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanup(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == batteryService }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([batteryCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == batteryCharacteristic }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { central?.cancelPeripheralConnection(peripheral) }
        guard characteristic.uuid == batteryCharacteristic,
              let data = characteristic.value, let byte = data.first else { return }

        let percent = Int(byte)
        let device = Device(
            id: "gatt-\(peripheral.identifier.uuidString)",
            name: peripheral.name ?? DeviceKind.headphones.displayName,
            kind: .headphones,
            overallPercent: percent,
            isCharging: false,
            lastSeen: Date(),
            source: .gattBLE,
            isConnected: true
        )
        results[peripheral.identifier] = device
        publish()
    }
}
