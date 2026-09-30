import Foundation
import CoreBluetooth

struct NearbyAdvertisement {
    let name: String
    let rssi: Int
    let batteryPercent: Int?
}

/// Scans BLE for Apple Continuity proximity-pairing advertisements and decodes AirPods/Beats
/// battery levels. Scan-only: it never connects, so it never disrupts an active audio session.
///
/// Limitations (inherent to the public approach): AirPods only broadcast for a short window
/// (typically when the case lid is opened), battery is ~10% granular, and the BLE address
/// rotates so there is no stable per-device identifier across sessions.
final class AirPodsScanner: NSObject, ObservableObject {

    /// Called on the main queue whenever the set of nearby AirPods changes.
    var onDevicesChanged: (([Device]) -> Void)?
    /// Includes other advertising devices so paired peripherals can be recognized nearby.
    var onNearbyAdvertisement: ((NearbyAdvertisement) -> Void)?
    /// Called on the main queue whenever Bluetooth authorization changes.
    var onAuthorizationChanged: ((CBManagerAuthorization) -> Void)?
    /// Called on the main queue whenever the Bluetooth power state changes.
    var onStateChanged: ((CBManagerState) -> Void)?

    private var central: CBCentralManager?
    private let queue = DispatchQueue(label: "com.batlet.airpods-scanner")

    /// Discovered devices keyed by the peripheral identifier, with the last-seen time.
    private var discovered: [UUID: Device] = [:]
    private var pruneTimer: DispatchSourceTimer?

    /// Devices unseen for longer than this are dropped from the Dashboard.
    private let staleInterval: TimeInterval = 30

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: queue,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        startPruneTimer()
    }

    var authorization: CBManagerAuthorization { CBManager.authorization }

    private func startPruneTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.pruneStale() }
        timer.resume()
        pruneTimer = timer
    }

    private func pruneStale() {
        let now = Date()
        let before = discovered.count
        discovered = discovered.filter { now.timeIntervalSince($0.value.lastSeen) < staleInterval }
        if discovered.count != before { publish() }
    }

    private func publish() {
        let devices = Array(discovered.values)
        DispatchQueue.main.async { [weak self] in
            self?.onDevicesChanged?(devices)
        }
    }

    private func beginScanning() {
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

extension AirPodsScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let auth = CBManager.authorization
        let state = central.state
        DispatchQueue.main.async { [weak self] in
            self?.onAuthorizationChanged?(auth)
            self?.onStateChanged?(state)
        }
        switch central.state {
        case .poweredOn:
            beginScanning()
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            discovered.removeAll()
            publish()
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let ad = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .flatMap { ContinuityParser.parse(manufacturerData: $0) }
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        let device = ad.map {
            Device.from(advertisement: $0, id: peripheral.identifier.uuidString,
                        name: advertisedName ?? $0.kind.displayName, rssi: RSSI.intValue)
        }
        if let advertisedName, !advertisedName.isEmpty, RSSI.intValue >= -85 {
            let nearby = NearbyAdvertisement(name: advertisedName, rssi: RSSI.intValue,
                                             batteryPercent: device?.overallPercent)
            DispatchQueue.main.async { [weak self] in self?.onNearbyAdvertisement?(nearby) }
        }

        guard let device else { return }
        discovered[peripheral.identifier] = device
        publish()
    }
}
