import Foundation
import Combine
import CoreBluetooth
import IOBluetooth

/// Central aggregator the UI observes. Merges battery readings from all sources
/// (Continuity BLE, GATT BLE, IOKit power, system_profiler, trusted mobile
/// devices) into a single device list.
@MainActor
final class DeviceStore: NSObject, ObservableObject {
    static let shared = DeviceStore()

    @Published private(set) var devices: [Device] = []
    @Published private(set) var bluetoothAuthorization: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var bluetoothPoweredOn: Bool = false
    @Published private(set) var hasLoadedBluetoothInventory = false
    let connectionEvents = PassthroughSubject<Device, Never>()
    let nearbyAdvertisements = PassthroughSubject<NearbyAdvertisement, Never>()

    private let airPodsScanner = AirPodsScanner()
    private let gattReader = BLEBatteryReader()
    private let mobileDeviceSource = MobileDeviceSource()

    // Latest snapshot per source.
    private var macDevice: Device?
    private var inventory: [Device] = []
    private var continuity: [Device] = []
    private var gatt: [Device] = []
    private var mobile: [Device] = []

    private var pollTimer: Timer?
    private var started = false
    private var refreshGeneration = 0
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var connectionOverrides: [String: ConnectionOverride] = [:]
    private var profilerBatteryByAddress: [String: BatteryReading] = [:]
    private var gattBatteryByID: [String: BatteryReading] = [:]
    private static let batteryReadingLifetime: TimeInterval = 5 * 60

    private struct ConnectionOverride {
        var device: Device
        let recordedAt: Date
    }

    private struct BatteryReading {
        let percent: Int
        let isCharging: Bool
        let source: BatteryReadingSource
        let recordedAt: Date

        func isFresh(at now: Date) -> Bool {
            let age = now.timeIntervalSince(recordedAt)
            return age >= 0 && age <= DeviceStore.batteryReadingLifetime
        }
    }

    // MARK: - Lifecycle

    /// Begins reading from all sources. Safe to call once permissions are resolved.
    func start() {
        guard !started else { return }
        started = true

        airPodsScanner.onDevicesChanged = { [weak self] devices in
            self?.continuity = devices
            self?.recombine()
        }
        airPodsScanner.onNearbyAdvertisement = { [weak self] advertisement in
            self?.nearbyAdvertisements.send(advertisement)
        }
        airPodsScanner.onAuthorizationChanged = { [weak self] auth in
            self?.bluetoothAuthorization = auth
        }
        airPodsScanner.onStateChanged = { [weak self] state in
            self?.bluetoothPoweredOn = (state == .poweredOn)
        }
        gattReader.onDevicesChanged = { [weak self] devices in
            self?.applyGATT(devices)
        }
        mobileDeviceSource.onDevicesChanged = { [weak self] devices in
            self?.applyMobileDevices(devices)
        }

        airPodsScanner.start()
        gattReader.start()
        mobileDeviceSource.start()
        observeBluetoothConnections()

        refreshSystemSources()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemSources() }
        }
    }

    /// Re-reads the Mac battery and system_profiler inventory (the polled sources).
    func refreshSystemSources() {
        refreshMacBattery()
        mobileDeviceSource.refresh()
        refreshGeneration += 1
        let generation = refreshGeneration
        Task.detached(priority: .utility) {
            let items = BluetoothInventory.fetch()
            await MainActor.run {
                guard generation == self.refreshGeneration, let items else { return }
                self.applyInventory(items)
            }
        }
    }

    func refreshMacBattery() {
        macDevice = SystemBatterySource.macDevice()
        recombine()
    }

    func refreshAllSources() {
        refreshSystemSources()
        gattReader.refresh()
    }

    func applyInventory(_ items: [Device], at now: Date = Date()) {
        var resolved = items
        var settledAddresses: [String] = []
        for (address, override) in connectionOverrides {
            let index = resolved.firstIndex { Self.addressKey($0.id) == address }
            if let index, resolved[index].isConnected == override.device.isConnected {
                settledAddresses.append(address)
            } else if now.timeIntervalSince(override.recordedAt) < 60 {
                if let index {
                    resolved[index].isConnected = override.device.isConnected
                } else {
                    resolved.append(override.device)
                }
            } else {
                settledAddresses.append(address)
            }
        }
        for address in settledAddresses { connectionOverrides.removeValue(forKey: address) }

        for index in resolved.indices {
            let address = Self.addressKey(resolved[index].id)
            guard !address.isEmpty else { continue }
            if resolved[index].isConnected {
                let reportedConnected = items.first {
                    Self.addressKey($0.id) == address
                }?.isConnected ?? resolved[index].isConnected
                if reportedConnected, let percent = resolved[index].overallPercent {
                    profilerBatteryByAddress[address] = BatteryReading(
                        percent: percent, isCharging: resolved[index].isCharging,
                        source: resolved[index].batteryReadingSource ?? .systemProfiler,
                        recordedAt: now
                    )
                } else if !reportedConnected {
                    // An old disconnected snapshot may contain a stale battery field.
                    resolved[index].overallPercent = nil
                    resolved[index].batteryReadingSource = nil
                }
            } else {
                profilerBatteryByAddress.removeValue(forKey: address)
            }
        }
        inventory = resolved
        recombine(at: now)
        hasLoadedBluetoothInventory = true
    }

    func applyGATT(_ devices: [Device], at now: Date = Date()) {
        gatt = devices
        for device in devices where device.isConnected {
            guard let percent = device.overallPercent else { continue }
            let name = Self.normalizedName(device.name)
            let matches = inventory.filter { Self.normalizedName($0.name) == name }
            let key: String
            if matches.count > 1 {
                guard let connected = matches.filter(\.isConnected).onlyElement else { continue }
                key = connected.id
            } else {
                key = name
            }
            gattBatteryByID[key] = BatteryReading(percent: percent,
                                                   isCharging: device.isCharging,
                                                   source: .gattBLE,
                                                   recordedAt: now)
        }
        recombine(at: now)
    }

    func applyMobileDevices(_ devices: [Device]) {
        mobile = devices
        recombine()
    }

    func processBluetoothEvent(address: String, name: String?, connected: Bool) {
        let key = Self.addressKey(address)
        guard !key.isEmpty else { refreshAfterBluetoothEvent(); return }

        let index = inventory.firstIndex { Self.addressKey($0.id) == key }
        if let index {
            let wasConnected = inventory[index].isConnected
            inventory[index].isConnected = connected
            if !connected || !wasConnected {
                inventory[index].overallPercent = nil
                inventory[index].batteryReadingSource = nil
                inventory[index].isCharging = false
            }
            connectionOverrides[key] = ConnectionOverride(device: inventory[index], recordedAt: Date())
        } else {
            let deviceName = name ?? "Bluetooth Device"
            let device = Device(id: "bt-\(address)", name: deviceName,
                                kind: BluetoothInventory.classify(name: deviceName, minorType: ""),
                                source: .systemProfiler, isConnected: connected)
            inventory.append(device)
            connectionOverrides[key] = ConnectionOverride(device: device, recordedAt: Date())
        }
        if !connected { profilerBatteryByAddress.removeValue(forKey: key) }

        recombine()
        let eventName = inventory.first { Self.addressKey($0.id) == key }?.name
        if let changed = devices.first(where: { Self.addressKey($0.id) == key })
            ?? devices.first(where: { $0.name == eventName && $0.isConnected == connected }) {
            connectionEvents.send(changed)
        }
        if connected { gattReader.refresh() }
        refreshAfterBluetoothEvent()
    }

    private static func addressKey(_ address: String) -> String {
        let raw = address.hasPrefix("bt-") ? String(address.dropFirst(3)) : address
        return String(raw.lowercased().filter(\.isHexDigit))
    }

    private func observeBluetoothConnections() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDidConnect(_:device:))
        )
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            where device.isConnected() {
            observeDisconnect(for: device)
        }
    }

    private func observeDisconnect(for device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(bluetoothDidDisconnect(_:device:))
        )
    }

    private func refreshAfterBluetoothEvent() {
        refreshSystemSources()
        // The connection notification can precede system_profiler updating its snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshSystemSources()
        }
    }

    @objc nonisolated private func bluetoothDidConnect(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        let address = device.addressString
        let name = device.name
        Task { @MainActor [weak self] in
            if let address, let device = IOBluetoothDevice(addressString: address) {
                self?.observeDisconnect(for: device)
            }
            if let address { self?.processBluetoothEvent(address: address, name: name, connected: true) }
        }
    }

    @objc nonisolated private func bluetoothDidDisconnect(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        let address = device.addressString
        let name = device.name
        Task { @MainActor [weak self] in
            if let address {
                self?.disconnectNotifications.removeValue(forKey: address)?.unregister()
                self?.processBluetoothEvent(address: address, name: name, connected: false)
            }
        }
    }

    // MARK: - Merging

    private func recombine(at now: Date = Date()) {
        var inventoryForMerge = inventory
        for index in inventoryForMerge.indices where inventoryForMerge[index].isConnected
            && inventoryForMerge[index].overallPercent == nil {
            let address = Self.addressKey(inventoryForMerge[index].id)
            if let cached = profilerBatteryByAddress[address], cached.isFresh(at: now) {
                inventoryForMerge[index].overallPercent = cached.percent
                inventoryForMerge[index].batteryReadingSource = cached.source
                inventoryForMerge[index].isCharging = cached.isCharging
            } else {
                profilerBatteryByAddress.removeValue(forKey: address)
            }
        }
        var merged = Self.mergedDevices(
            macDevice: macDevice, inventory: inventoryForMerge, continuity: continuity, gatt: gatt,
            mobile: mobile
        )
        for index in merged.indices where merged[index].source == .systemProfiler {
            let device = merged[index]
            if device.isConnected {
                if let cached = gattBatteryByID[device.id], cached.isFresh(at: now),
                   (device.batteryReadingSource?.rawValue ?? 0) < cached.source.rawValue {
                    merged[index].overallPercent = cached.percent
                    merged[index].batteryReadingSource = cached.source
                    merged[index].isCharging = cached.isCharging
                } else if gattBatteryByID[device.id]?.isFresh(at: now) != true {
                    gattBatteryByID.removeValue(forKey: device.id)
                }
            } else {
                gattBatteryByID.removeValue(forKey: device.id)
            }
        }
        devices = merged
    }

    /// Keeps distinct paired devices with the same name while merging readings from
    /// other sources into an unambiguous system_profiler entry.
    static func mergedDevices(
        macDevice: Device?, inventory: [Device], continuity: [Device], gatt: [Device],
        mobile: [Device] = []
    ) -> [Device] {
        var byKey: [String: Device] = [:]
        let inventoryByName = Dictionary(grouping: inventory, by: { normalizedName($0.name) })

        func consider(_ device: Device) {
            let nameKey = normalizedName(device.name)
            let matches = inventoryByName[nameKey] ?? []
            let key: String
            if device.source == .systemPower {
                key = "mac"
            } else if device.source == .mobileDevice {
                key = device.id // Multiple trusted mobile devices can share one name.
            } else if matches.count > 1 {
                if device.source == .systemProfiler {
                    key = device.id
                } else if let connected = matches.filter(\.isConnected).onlyElement {
                    key = connected.id
                } else {
                    key = nameKey
                }
            } else {
                key = nameKey
            }

            if let existing = byKey[key] {
                byKey[key] = Self.preferred(existing, device)
            } else {
                byKey[key] = device
            }
        }

        if let macDevice { consider(macDevice) }
        inventory.forEach(consider)
        continuity.forEach(consider)
        gatt.forEach(consider)
        mobile.forEach(consider)

        return byKey
            .map { key, device -> Device in
                var d = device
                d.id = key   // stable identity across source changes
                return d
            }
            .sorted(by: Self.sort)
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Higher priority source wins when the same device is reported twice.
    private static func priority(_ source: DeviceSource) -> Int {
        switch source {
        case .systemPower: return 5     // this Mac (unique)
        case .mobileDevice: return 4    // trusted iPhone / iPad, exact %
        case .systemProfiler: return 3  // paired-device identity and connection state
        case .continuityBLE: return 2   // works when not connected, ~10% steps
        case .gattBLE: return 1
        }
    }

    private static func preferred(_ a: Device, _ b: Device) -> Device {
        let preferA = priority(a.source) >= priority(b.source)
        var chosen = preferA ? a : b
        let other = preferA ? b : a
        if a.source == .systemProfiler {
            chosen.isConnected = a.isConnected
        } else if b.source == .systemProfiler {
            chosen.isConnected = b.isConnected
        } else {
            chosen.isConnected = a.isConnected || b.isConnected
        }
        if chosen.isConnected, other.overallPercent != nil,
           (chosen.overallPercent == nil ||
            (other.batteryReadingSource?.rawValue ?? 0) > (chosen.batteryReadingSource?.rawValue ?? 0)) {
            chosen.overallPercent = other.overallPercent
            chosen.batteryReadingSource = other.batteryReadingSource
            chosen.isCharging = other.isCharging
            chosen.left = other.left
            chosen.right = other.right
            chosen.caseComponent = other.caseComponent
        } else if chosen.overallPercent == nil, other.overallPercent != nil {
            chosen.overallPercent = other.overallPercent
            chosen.batteryReadingSource = other.batteryReadingSource
            chosen.isCharging = other.isCharging
            chosen.left = other.left
            chosen.right = other.right
            chosen.caseComponent = other.caseComponent
        }
        return chosen
    }

    private static func sort(_ a: Device, _ b: Device) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
        if a.isConnected != b.isConnected { return a.isConnected && !b.isConnected }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

private extension Collection {
    var onlyElement: Element? { count == 1 ? first : nil }
}
