import IOKit.ps
import XCTest
@testable import Batlet

final class SystemBatterySourceTests: XCTestCase {
    func testExternalPowerIsReportedWhenChargingIsPaused() {
        let device = SystemBatterySource.device(
            from: description(powerState: kIOPSACPowerValue as String, isCharging: false),
            name: "Test Mac"
        )

        XCTAssertEqual(device?.overallPercent, 80)
        XCTAssertEqual(device?.isCharging, false)
        XCTAssertEqual(device?.isConnectedToPower, true)
    }

    func testBatteryPowerDoesNotShowPlug() {
        let device = SystemBatterySource.device(
            from: description(powerState: kIOPSBatteryPowerValue as String, isCharging: false),
            name: "Test Mac"
        )

        XCTAssertEqual(device?.isConnectedToPower, false)
    }

    private func description(powerState: String, isCharging: Bool) -> [String: Any] {
        [
            kIOPSTypeKey as String: kIOPSInternalBatteryType as String,
            kIOPSCurrentCapacityKey as String: 80,
            kIOPSMaxCapacityKey as String: 100,
            kIOPSIsChargingKey as String: isCharging,
            kIOPSPowerSourceStateKey as String: powerState
        ]
    }
}
