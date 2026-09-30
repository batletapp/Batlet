import AppKit
import XCTest
@testable import Batlet

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testFirstOpenShowsFullHeightSettingsContent() {
        let delegate = AppDelegate()
        delegate.showSettings()

        guard let window = NSApp.windows.first(where: {
            $0.title == "Batlet Settings" && $0.isVisible
        }) else { return XCTFail("Settings window did not open") }
        defer { window.close() }

        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.height ?? 0, 500)
        XCTAssertGreaterThanOrEqual(window.frame.height, 520)

    }

    @MainActor
    func testSettingsWindowShowsDockIconUntilClosed() {
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(originalPolicy) }

        let delegate = AppDelegate()
        delegate.showSettings()

        guard let window = NSApp.windows.first(where: {
            $0.title == "Batlet Settings" && $0.isVisible
        }) else { return XCTFail("Settings window did not open") }

        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        window.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testBatteryDisplayTypeDefaultsToBarAndPersistsCircle() {
        let suiteName = "BatteryDisplayTypeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.batteryDisplayType, .bar)

        settings.batteryDisplayType = .circle
        XCTAssertEqual(AppSettings(defaults: defaults).batteryDisplayType, .circle)
    }

    func testBackgroundSuggestionsDefaultOffAndCanBeEnabled() {
        let suiteName = "NearbySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.nearbyPromptsEnabled)
        settings.nearbyPromptsEnabled = true
        XCTAssertTrue(AppSettings(defaults: defaults).nearbyPromptsEnabled)
    }

    func testNotificationStyleAndHubPlacementPersist() {
        let suiteName = "NotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.alertDisplayStyle, .alertBox)
        XCTAssertEqual(settings.hubVerticalPosition, .top)
        XCTAssertEqual(settings.hubHorizontalAlignment, .center)

        settings.alertDisplayStyle = .hub
        settings.hubVerticalPosition = .bottom
        settings.hubHorizontalAlignment = .right

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.alertDisplayStyle, .hub)
        XCTAssertEqual(restored.hubVerticalPosition, .bottom)
        XCTAssertEqual(restored.hubHorizontalAlignment, .right)
    }

    func testSystemNotificationsDefaultOnAndPersistOff() {
        let suiteName = "SystemNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.systemNotificationsEnabled)
        settings.systemNotificationsEnabled = false
        XCTAssertFalse(AppSettings(defaults: defaults).systemNotificationsEnabled)
    }

    @MainActor
    func testAddDeviceWindowOpensWithoutStartingBackgroundScan() {
        let delegate = AppDelegate()
        delegate.showAddDevice()

        guard let window = NSApp.windows.first(where: {
            $0.title == "Add Device" && $0.isVisible
        }) else { return XCTFail("Add Device window did not open") }
        defer { window.close() }

        XCTAssertFalse(NearbyDeviceManager.shared.isScanning)
        XCTAssertGreaterThanOrEqual(window.contentView?.bounds.width ?? 0, 500)
    }

}
