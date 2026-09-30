import XCTest
@testable import Batlet

final class BluetoothInventoryTests: XCTestCase {
    func testClassifiesNamedDevicesBeforeProfilerProvidesMinorType() {
        XCTAssertEqual(BluetoothInventory.classify(name: "MX Keys Mini", minorType: ""), .keyboard)
        XCTAssertEqual(BluetoothInventory.classify(name: "EK868 BT keyboard", minorType: ""), .keyboard)
        XCTAssertEqual(BluetoothInventory.classify(name: "MX Master 3S", minorType: ""), .mouse)
        XCTAssertEqual(BluetoothInventory.classify(name: "Magic Mouse", minorType: ""), .magicMouse)
    }

    func testPairedDevicesRemainVisibleWhenBatteryIsUnavailable() {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [
                    ["Desk Keyboard": ["device_address": "AA:BB:CC:01", "device_minorType": "Keyboard"]],
                    ["Magic Mouse": ["device_address": "AA:BB:CC:02", "device_minorType": "Mouse"]]
                ],
                "device_not_connected": [
                    ["Travel Earbuds": ["device_address": "AA:BB:CC:03", "device_minorType": "Headphones"]]
                ]
            ]]
        ]

        let devices = BluetoothInventory.parse(json: json)

        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices.filter(\.isConnected).count, 2)
        XCTAssertEqual(devices.filter { !$0.isConnected }.count, 1)
        XCTAssertTrue(devices.allSatisfy { $0.overallPercent == nil })
        XCTAssertEqual(devices.first(where: { $0.name == "Magic Mouse" })?.kind, .magicMouse)
    }

    @MainActor
    func testMergingKeepsSameNamePairedDevicesDistinct() {
        let first = Device(id: "bt-01", name: "Travel Mouse", kind: .mouse,
                           source: .systemProfiler, isConnected: true)
        let second = Device(id: "bt-02", name: "Travel Mouse", kind: .mouse,
                            source: .systemProfiler, isConnected: false)
        let battery = Device(id: "gatt-01", name: "Travel Mouse", kind: .mouse,
                             overallPercent: 73, source: .gattBLE, isConnected: true)

        let result = DeviceStore.mergedDevices(
            macDevice: nil, inventory: [first, second], continuity: [], gatt: [battery]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.id)), Set(["bt-01", "bt-02"]))
        XCTAssertEqual(result.first(where: { $0.id == "bt-01" })?.overallPercent, 73)
        XCTAssertNil(result.first(where: { $0.id == "bt-02" })?.overallPercent)
    }

    @MainActor
    func testProfilerDisconnectionOverridesStaleGATTConnection() {
        let disconnected = Device(id: "bt-01", name: "Headset", kind: .headphones,
                                  source: .systemProfiler, isConnected: false)
        let staleReading = Device(id: "gatt-01", name: "Headset", kind: .headphones,
                                  overallPercent: 60, source: .gattBLE, isConnected: true)

        let result = DeviceStore.mergedDevices(
            macDevice: nil, inventory: [disconnected], continuity: [], gatt: [staleReading]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.isConnected, false)
        XCTAssertEqual(result.first?.overallPercent, 60)
    }

    func testConnectedHIDBatteryFillsMissingProfilerLevel() {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [
                    ["Magic Mouse": ["device_address": "AA:BB:CC:01", "device_minorType": "Mouse"]]
                ],
                "device_not_connected": [
                    ["Old Mouse": ["device_address": "AA:BB:CC:02", "device_minorType": "Mouse"]]
                ]
            ]]
        ]

        let devices = BluetoothInventory.parse(
            json: json, batteryByAddress: ["aabbcc01": 82, "aabbcc02": 64]
        )

        XCTAssertEqual(devices.first(where: { $0.name == "Magic Mouse" })?.overallPercent, 82)
        XCTAssertNil(devices.first(where: { $0.name == "Old Mouse" })?.overallPercent)
    }

    @MainActor
    func testAccessoryPowerReadingBeatsIncorrectProfilerAndGATTLevels() {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [["AULA-S75Pro-1": [
                    "device_address": "AA:BB:CC:DD:EE:FF",
                    "device_minorType": "Keyboard",
                    "device_batteryLevelMain": "94%"
                ]]]
            ]]
        ]
        let devices = BluetoothInventory.parse(
            json: json, accessoryBatteryByName: ["aula-s75pro-1": 42]
        )
        XCTAssertEqual(devices.first?.overallPercent, 42)
        XCTAssertEqual(devices.first?.batteryReadingSource, .accessoryPower)

        let store = DeviceStore()
        store.applyInventory(devices)
        let gatt = Device(id: "gatt-123", name: "AULA-S75Pro-1", kind: .keyboard,
                          overallPercent: 94, source: .gattBLE, isConnected: true)
        store.applyGATT([gatt])
        XCTAssertEqual(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent, 42)

        store.applyGATT([])
        XCTAssertEqual(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent, 42)
    }

    func testAccessoryPowerReadingRequiresUniqueConnectedName() {
        let json: [String: Any] = [
            "SPBluetoothDataType": [[
                "device_connected": [
                    ["Desk Keyboard": ["device_address": "AA:BB:CC:01"]],
                    ["Desk Keyboard": ["device_address": "AA:BB:CC:02"]]
                ]
            ]]
        ]
        let devices = BluetoothInventory.parse(
            json: json, accessoryBatteryByName: ["desk keyboard": 42]
        )
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices.allSatisfy { $0.overallPercent == nil })
    }

    func testAccessoryPowerSourceParsesOnlyValidBluetoothReadings() {
        let descriptions: [[String: Any]] = [
            ["Type": "Accessory Source", "Transport Type": "Bluetooth",
             "Name": " AULA-S75Pro-1 ", "Current Capacity": 42, "Max Capacity": 100],
            ["Type": "Accessory Source", "Transport Type": "USB",
             "Name": "USB Device", "Current Capacity": 50, "Max Capacity": 100],
            ["Type": "Accessory Source", "Transport Type": "Bluetooth",
             "Name": "Invalid", "Current Capacity": 120, "Max Capacity": 100]
        ]

        XCTAssertEqual(BluetoothAccessoryBatterySource.levels(from: descriptions),
                       ["aula-s75pro-1": 42])

        let duplicate = descriptions[0].merging(["Current Capacity": 55]) { _, new in new }
        let duplicateLevels = BluetoothAccessoryBatterySource.levels(from: [descriptions[0], duplicate])
        XCTAssertNil(duplicateLevels["aula-s75pro-1"])
    }

    @MainActor
    func testConnectedBatterySurvivesProfilerSnapshotWithoutLevel() {
        let store = DeviceStore()
        let connected = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                               kind: .magicKeyboard, overallPercent: 80,
                               source: .systemProfiler, isConnected: true)
        var noLevel = connected
        noLevel.overallPercent = nil

        store.applyInventory([connected])
        store.applyInventory([noLevel])
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent, 80)

        store.processBluetoothEvent(address: "AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                                    connected: false)
        store.processBluetoothEvent(address: "AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                                    connected: true)
        XCTAssertNil(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent)

        var staleDisconnected = connected
        staleDisconnected.isConnected = false
        store.applyInventory([staleDisconnected])
        XCTAssertNil(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent)

        var freshReading = connected
        freshReading.overallPercent = 79
        store.applyInventory([freshReading])
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent, 79)
    }

    @MainActor
    func testTemporaryGATTReadRemainsVisibleWhileKeyboardIsConnected() {
        let store = DeviceStore()
        let keyboard = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                              kind: .keyboard, source: .systemProfiler, isConnected: true)
        let gattReading = Device(id: "gatt-123", name: "MX Keys Mini", kind: .keyboard,
                                 overallPercent: 80, source: .gattBLE, isConnected: true)

        store.applyInventory([keyboard])
        store.applyGATT([gattReading])
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent, 80)

        store.applyGATT([]) // The brief GATT read connection is closed after reading.
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent, 80)

        store.processBluetoothEvent(address: "AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                                    connected: false)
        XCTAssertNil(store.devices.first { $0.name == "MX Keys Mini" }?.overallPercent)
    }

    @MainActor
    func testFreshGATTReadingReplacesOlderProfilerBattery() {
        let store = DeviceStore()
        let keyboard = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "Desk Keyboard",
                              kind: .keyboard, overallPercent: 94,
                              source: .systemProfiler, isConnected: true)
        let currentReading = Device(id: "gatt-123", name: "Desk Keyboard",
                                    kind: .keyboard, overallPercent: 42,
                                    source: .gattBLE, isConnected: true)

        store.applyInventory([keyboard])
        store.applyGATT([currentReading])
        XCTAssertEqual(store.devices.first { $0.name == "Desk Keyboard" }?.overallPercent, 42)

        store.applyGATT([]) // A brief GATT read must remain visible between polls.
        XCTAssertEqual(store.devices.first { $0.name == "Desk Keyboard" }?.overallPercent, 42)
    }

    @MainActor
    func testCachedBatteryExpiresWhenProfilerStopsReporting() {
        let store = DeviceStore()
        let firstReading = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "AULA-S75Pro-1",
                                  kind: .keyboard, overallPercent: 94,
                                  source: .systemProfiler, isConnected: true)
        var noReading = firstReading
        noReading.overallPercent = nil
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

        store.applyInventory([firstReading], at: start)
        store.applyInventory([noReading], at: start.addingTimeInterval(60))
        XCTAssertEqual(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent, 94)

        store.applyInventory([noReading], at: start.addingTimeInterval(301))
        XCTAssertNil(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent)
    }

    @MainActor
    func testTemporaryGATTReadingAlsoExpiresWithoutRefresh() {
        let store = DeviceStore()
        let keyboard = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "AULA-S75Pro-1",
                              kind: .keyboard, source: .systemProfiler, isConnected: true)
        let gattReading = Device(id: "gatt-123", name: "AULA-S75Pro-1",
                                 kind: .keyboard, overallPercent: 42,
                                 source: .gattBLE, isConnected: true)
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

        store.applyInventory([keyboard], at: start)
        store.applyGATT([gattReading], at: start)
        store.applyGATT([], at: start.addingTimeInterval(60))
        XCTAssertEqual(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent, 42)

        store.applyInventory([keyboard], at: start.addingTimeInterval(301))
        XCTAssertNil(store.devices.first { $0.name == "AULA-S75Pro-1" }?.overallPercent)
    }

}
