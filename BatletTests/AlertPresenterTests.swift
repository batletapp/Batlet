import AppKit
import SwiftUI
import XCTest
import UserNotifications
@testable import Batlet

final class AlertPresenterTests: XCTestCase {
    @MainActor
    func testNotificationPreviewUsesSoundToggleAndImmediateRequest() async {
        let (settings, cleanupSettings) = notificationSettings()
        defer { cleanupSettings() }
        let client = FakeBatteryNotificationClient()
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)

        let audible = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                            style: .notification, playSound: true)
        XCTAssertEqual(audible, .notificationSent)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertNil(client.requests[0].trigger)
        XCTAssertNotNil(client.requests[0].content.sound)

        let silent = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                           style: .notification, playSound: false)
        XCTAssertEqual(silent, .notificationSent)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertNil(client.requests[1].content.sound)
    }

    @MainActor
    func testCustomNotificationSoundIsUsedAndBundled() async {
        let (settings, cleanupSettings) = notificationSettings()
        defer { cleanupSettings() }
        let client = FakeBatteryNotificationClient()
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)
        for choice in AlertSound.allCases {
            guard let fileName = choice.fileName else { continue }
            guard let url = AlertSoundPlayer.url(for: fileName) else {
                return XCTFail("Missing sound: \(fileName)")
            }
            XCTAssertNotNil(NSSound(contentsOf: url, byReference: true))
        }

        let result = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                           style: .notification, playSound: true, sound: .bell)
        XCTAssertEqual(result, .notificationSent)
        XCTAssertEqual(client.requests.first?.content.sound,
                       UNNotificationSound(named: UNNotificationSoundName(rawValue: "AlertBell.wav")))
    }

    func testExistingAlertsDefaultToSystemSound() throws {
        var alert = BatteryAlert(deviceKey: "keyboard", deviceName: "Keyboard", kind: .keyboard)
        alert.selectedSound = .ripple
        let saved = try JSONDecoder().decode(BatteryAlert.self, from: JSONEncoder().encode(alert))
        XCTAssertEqual(saved.selectedSound, .ripple)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(alert)) as? [String: Any])
        legacy.removeValue(forKey: "soundName")
        let oldAlert = try JSONDecoder().decode(BatteryAlert.self,
                                                from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(oldAlert.selectedSound, .systemDefault)
    }

    @MainActor
    func testSavedSoundIsUsedForARealLowBatteryAlert() {
        let suiteName = "BatterySoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        var alert = BatteryAlert(deviceKey: "desk keyboard", deviceName: "Desk Keyboard",
                                 kind: .keyboard, lowThreshold: 20, style: .notification)
        alert.selectedSound = .pulse
        settings.batteryAlerts = [alert]

        let client = FakeBatteryNotificationClient()
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)
        let store = DeviceStore()
        manager.start(store: store, settings: settings)
        store.applyInventory([Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "Desk Keyboard",
                                     kind: .keyboard, overallPercent: 10,
                                     source: .systemProfiler, isConnected: true)])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.content.sound,
                       UNNotificationSound(named: UNNotificationSoundName(rawValue: "AlertPulse.wav")))
    }

    @MainActor
    func testSystemNotificationToggleSuppressesDeliveryAndPreview() async {
        let suiteName = "SystemNotificationToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.systemNotificationsEnabled = false
        settings.batteryAlerts = [BatteryAlert(
            deviceKey: "desk keyboard", deviceName: "Desk Keyboard", kind: .keyboard,
            lowThreshold: 20, style: .notification
        )]

        let client = FakeBatteryNotificationClient()
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)
        let store = DeviceStore()
        manager.start(store: store, settings: settings)
        store.applyInventory([Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "Desk Keyboard",
                                     kind: .keyboard, overallPercent: 10,
                                     source: .systemProfiler, isConnected: true)])
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.requests.isEmpty)

        let result = await manager.preview(kind: .keyboard, name: "Desk Keyboard", threshold: 20,
                                           style: .notification, playSound: true)
        XCTAssertEqual(result, .appNotificationsDisabled)
        XCTAssertTrue(client.requests.isEmpty)
    }

    @MainActor
    func testPreviewRequestsPermissionBeforeSendingNotification() async {
        let (settings, cleanupSettings) = notificationSettings()
        defer { cleanupSettings() }
        let client = FakeBatteryNotificationClient()
        client.configuration = BatteryNotificationSettings(
            authorizationStatus: .notDetermined, alertsEnabled: false, soundsEnabled: false
        )
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)

        let result = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                           style: .notification, playSound: true)
        XCTAssertTrue(client.requestedAuthorization)
        XCTAssertEqual(result, .notificationSent)
        XCTAssertEqual(client.requests.count, 1)
    }

    @MainActor
    func testPreviewExplainsWhenNotificationsAreDisabled() async {
        let (settings, cleanupSettings) = notificationSettings()
        defer { cleanupSettings() }
        let client = FakeBatteryNotificationClient()
        client.configuration = BatteryNotificationSettings(
            authorizationStatus: .denied, alertsEnabled: false, soundsEnabled: false
        )
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)

        let result = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                           style: .notification, playSound: true)
        XCTAssertEqual(result, .permissionDenied)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(result.needsSystemSettings)
    }

    @MainActor
    func testPreviewExplainsWhenNotificationSoundsAreDisabled() async {
        let (settings, cleanupSettings) = notificationSettings()
        defer { cleanupSettings() }
        let client = FakeBatteryNotificationClient()
        client.configuration = BatteryNotificationSettings(
            authorizationStatus: .authorized, alertsEnabled: true, soundsEnabled: false
        )
        let manager = BatteryAlertManager(notificationClient: client, settings: settings)

        let result = await manager.preview(kind: .keyboard, name: "Keyboard", threshold: 10,
                                           style: .notification, playSound: true)
        XCTAssertEqual(result, .soundDisabled)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(result.needsSystemSettings)
    }

    func testConnectionArtworkUsesBundledImagesAndFallsBackForMissingKinds() {
        let expected: [DeviceKind: String] = [
            .airpods: "ConnectionAirPods", .airpodsPro: "ConnectionAirPods",
            .airpodsMax: "ConnectionAirPods", .airpods3: "ConnectionAirPods",
            .airpodsPro2: "ConnectionAirPods", .airpods4: "ConnectionAirPods",
            .beats: "ConnectionHeadphones", .headphones: "ConnectionHeadphones",
            .magicMouse: "ConnectionMagicMouse", .mouse: "ConnectionMouse",
            .magicKeyboard: "ConnectionKeyboard", .keyboard: "ConnectionKeyboard",
            .magicTrackpad: "ConnectionTrackpad", .trackpad: "ConnectionTrackpad",
            .iphone: "ConnectionIPhone", .ipad: "ConnectionIPad",
            .watch: "ConnectionWatch"
        ]
        for (kind, name) in expected {
            XCTAssertEqual(ConnectionPopupImage.assetName(for: kind), name)
            XCTAssertNotNil(NSImage(named: name), "Missing image asset: \(name)")
        }
        for kind in [DeviceKind.mac, .macBook, .unknown] {
            XCTAssertNil(ConnectionPopupImage.assetName(for: kind))
        }
    }

    func testBatteryLevelBoundariesAndChargingHint() {
        func alert(_ percent: Int, isCharging: Bool = false) -> AlertPresentation {
            AlertPresentation(title: "Headphones", subtitle: "Connected successfully",
                              symbol: "headphones", percent: percent, tone: .success,
                              connectionDeviceID: "headphones", isCharging: isCharging)
        }

        XCTAssertEqual(alert(21).batteryLevel, .healthy)
        XCTAssertEqual(alert(20).batteryLevel, .low)
        XCTAssertEqual(alert(10).batteryLevel, .low)
        XCTAssertEqual(alert(9).batteryLevel, .critical)
        XCTAssertFalse(alert(20).recommendsCharging)
        XCTAssertTrue(alert(19).recommendsCharging)
        XCTAssertTrue(alert(9).recommendsCharging)
        XCTAssertFalse(alert(9, isCharging: true).recommendsCharging)
    }

    @MainActor
    func testBatteryReadingUpdatesVisibleAndQueuedConnectionAlerts() {
        let (settings, cleanupSettings) = alertBoxSettings()
        defer { cleanupSettings() }
        let presenter = AlertPresenter(settings: settings)
        defer { presenter.dismiss(); presenter.dismiss() }
        presenter.show(AlertPresentation(
            title: "Keyboard", subtitle: "Connected successfully", symbol: "keyboard",
            percent: nil, tone: .success, autoDismiss: 30, connectionDeviceID: "keyboard",
            deviceImageName: "ConnectionKeyboard", isConnectionEvent: true
        ))
        presenter.show(AlertPresentation(
            title: "Mouse", subtitle: "Connected successfully", symbol: "magicmouse",
            percent: nil, tone: .success, autoDismiss: 30, connectionDeviceID: "mouse",
            deviceImageName: "ConnectionMagicMouse", isConnectionEvent: true
        ))

        let initialMidY = presenter.currentPanel?.frame.midY
        XCTAssertEqual(presenter.currentPanel?.frame.height, 236)
        presenter.updateConnectionBattery(for: "keyboard", percent: 19, isCharging: false)
        presenter.updateConnectionBattery(for: "mouse", percent: 8, isCharging: false)
        let first = presenter.currentPanel
        XCTAssertEqual(first?.frame.height, 284)
        XCTAssertEqual(first?.frame.midY, initialMidY)
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.percent, 19)
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.recommendsCharging,
                       true)

        presenter.dismiss()
        let second = presenter.currentPanel
        XCTAssertEqual(second?.frame.height, 284)
        XCTAssertEqual((second?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.percent, 8)
        XCTAssertEqual((second?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.batteryLevel,
                       .critical)
    }

    @MainActor
    func testPopupIsCenteredAndQueuedAlertsAreShownInOrder() {
        let (settings, cleanupSettings) = alertBoxSettings()
        defer { cleanupSettings() }
        let presenter = AlertPresenter(settings: settings)
        defer { presenter.dismiss(); presenter.dismiss() }

        presenter.show(AlertPresentation(
            title: "First Device", subtitle: "Connected successfully",
            symbol: "headphones", percent: 80, tone: .success, autoDismiss: 30
        ))
        presenter.show(AlertPresentation(
            title: "Second Device", subtitle: "Battery Low",
            symbol: "magicmouse", percent: 10, tone: .warning, autoDismiss: 30
        ))

        guard let first = presenter.currentPanel, first.isVisible,
              let screen = first.screen ?? NSScreen.main
        else { return XCTFail("The popup panel was not visible") }

        XCTAssertEqual(first.frame.midX, screen.visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(first.frame.midY, screen.visibleFrame.midY, accuracy: 1)
        XCTAssertFalse(first.hidesOnDeactivate, "Alert must remain visible while the menu bar app is inactive")
        XCTAssertFalse(first.hasShadow, "The window shadow must not outline the rectangular panel")
        XCTAssertEqual(first.frame.width, CenteredAlertView.width)
        XCTAssertEqual(first.frame.height, CenteredAlertView.height)
        XCTAssertEqual((first.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.title,
                       "First Device")

        presenter.dismiss()

        let second = presenter.currentPanel
        XCTAssertEqual((second?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.title,
                       "Second Device")
    }

    @MainActor
    func testHubUsesCompactLayoutAndKeepsEdgeWhenBatteryArrives() {
        let suiteName = "HubPresenterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.alertDisplayStyle = .hub
        settings.hubVerticalPosition = .top
        settings.hubHorizontalAlignment = .right
        let presenter = AlertPresenter(settings: settings)
        defer { presenter.dismiss() }

        presenter.show(AlertPresentation(
            title: "Keyboard", subtitle: "Connected successfully", symbol: "keyboard",
            percent: nil, tone: .success, autoDismiss: 30,
            connectionDeviceID: "keyboard", isConnectionEvent: true
        ))
        guard let panel = presenter.currentPanel,
              let screen = panel.screen ?? NSScreen.main else {
            return XCTFail("Hub panel was not visible")
        }
        XCTAssertEqual(panel.frame.width, HubAlertView.width)
        XCTAssertEqual(panel.frame.height, HubAlertView.height(for: (panel.contentView as! NSHostingView<HubAlertView>).rootView.alert))
        XCTAssertEqual(panel.frame.maxX, screen.visibleFrame.maxX - 16, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, screen.visibleFrame.maxY - 16, accuracy: 1)

        presenter.updateConnectionBattery(for: "keyboard", percent: 19, isCharging: false)
        XCTAssertEqual((panel.contentView as? NSHostingView<HubAlertView>)?.rootView.alert.percent, 19)
        XCTAssertEqual(panel.frame.maxX, screen.visibleFrame.maxX - 16, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, screen.visibleFrame.maxY - 16, accuracy: 1)
    }

    @MainActor
    func testHubFrameSupportsAllSixPositions() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1200, height: 800)
        let size = CGSize(width: 320, height: 98)
        for vertical in HubVerticalPosition.allCases {
            for horizontal in HubHorizontalAlignment.allCases {
                let frame = AlertPresenter.frame(for: size, in: visibleFrame, style: .hub,
                                                 vertical: vertical, horizontal: horizontal)
                XCTAssertEqual(frame.width, size.width)
                XCTAssertEqual(frame.height, size.height)
                XCTAssertEqual(vertical == .top ? frame.maxY : frame.minY,
                               vertical == .top ? visibleFrame.maxY - 16 : visibleFrame.minY + 16)
                switch horizontal {
                case .left: XCTAssertEqual(frame.minX, visibleFrame.minX + 16)
                case .center: XCTAssertEqual(frame.midX, visibleFrame.midX)
                case .right: XCTAssertEqual(frame.maxX, visibleFrame.maxX - 16)
                }
            }
        }
    }

    private func alertBoxSettings() -> (AppSettings, () -> Void) {
        let suiteName = "AlertPresenterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.alertDisplayStyle = .alertBox
        return (settings, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private func notificationSettings() -> (AppSettings, () -> Void) {
        let suiteName = "NotificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.systemNotificationsEnabled = true
        return (settings, { defaults.removePersistentDomain(forName: suiteName) })
    }
}

@MainActor
private final class FakeBatteryNotificationClient: BatteryNotificationClient {
    var configuration = BatteryNotificationSettings(
        authorizationStatus: .authorized, alertsEnabled: true, soundsEnabled: true
    )
    var requestedAuthorization = false
    var requests: [UNNotificationRequest] = []

    func settings() async -> BatteryNotificationSettings { configuration }

    func requestAuthorization() async -> Bool {
        requestedAuthorization = true
        configuration = BatteryNotificationSettings(
            authorizationStatus: .authorized, alertsEnabled: true, soundsEnabled: true
        )
        return true
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        requests.append(request)
        completion(nil)
    }
}
