import XCTest
@testable import Batlet

final class MobileDeviceSourceTests: XCTestCase {
    @MainActor
    func testTrustedPhonesWithTheSameNameKeepSeparateBatteryReadings() {
        let first = Device(id: "mobile-phone-a", name: "iPhone", kind: .iphone,
                           overallPercent: 54, source: .mobileDevice, isConnected: true)
        let second = Device(id: "mobile-phone-b", name: "iPhone", kind: .iphone,
                            overallPercent: 82, source: .mobileDevice, isConnected: true)

        let store = DeviceStore()
        store.applyMobileDevices([first, second])

        XCTAssertEqual(store.devices.count, 2)
        XCTAssertEqual(store.devices.first { $0.id == first.id }?.overallPercent, 54)
        XCTAssertEqual(store.devices.first { $0.id == second.id }?.overallPercent, 82)
    }

    @MainActor
    func testMobileDeviceDisappearsWhenTheTrustedDeviceDisconnects() {
        let phone = Device(id: "mobile-phone-a", name: "iPhone", kind: .iphone,
                           overallPercent: 54, source: .mobileDevice, isConnected: true)
        let keyboard = Device(id: "bt-01", name: "Desk Keyboard", kind: .keyboard,
                              overallPercent: 80, source: .systemProfiler, isConnected: true)
        let store = DeviceStore()

        store.applyMobileDevices([phone])
        store.applyInventory([keyboard])
        XCTAssertNotNil(store.devices.first { $0.kind == .iphone })

        store.applyMobileDevices([])
        XCTAssertNil(store.devices.first { $0.kind == .iphone })
        XCTAssertNotNil(store.devices.first { $0.name == "Desk Keyboard" })
    }
}
