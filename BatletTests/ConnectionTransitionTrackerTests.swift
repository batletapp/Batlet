import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Batlet

final class ConnectionTransitionTrackerTests: XCTestCase {
    private func device(_ id: String, connected: Bool, percent: Int? = nil) -> Device {
        Device(id: id, name: id, kind: .headphones, overallPercent: percent,
               source: .systemProfiler, isConnected: connected)
    }

    func testOnlyReportsChangesAfterInitialInventory() {
        var tracker = ConnectionTransitionTracker()
        let mouse = device("mouse", connected: true)

        XCTAssertTrue(tracker.transitions(in: [mouse], inventoryReady: false).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [mouse], inventoryReady: true).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [mouse], inventoryReady: true).isEmpty)

        let disconnected = device("mouse", connected: false)
        XCTAssertEqual(tracker.transitions(in: [disconnected], inventoryReady: true),
                       [.disconnected(disconnected)])
        XCTAssertTrue(tracker.transitions(in: [disconnected], inventoryReady: true).isEmpty)
        XCTAssertEqual(tracker.transitions(in: [mouse], inventoryReady: true), [.connected(mouse)])
        XCTAssertTrue(tracker.transitions(in: [device("mouse", connected: true, percent: 80)],
                                          inventoryReady: true).isEmpty)
    }

    func testNewlyConnectedDeviceAfterBaselineReportsOnce() {
        var tracker = ConnectionTransitionTracker()
        XCTAssertTrue(tracker.transitions(in: [], inventoryReady: true).isEmpty)

        let headset = device("headset", connected: true)
        XCTAssertEqual(tracker.transitions(in: [headset], inventoryReady: true), [.connected(headset)])
        XCTAssertTrue(tracker.transitions(in: [headset], inventoryReady: true).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [], inventoryReady: true).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [headset], inventoryReady: true).isEmpty)

        let disconnected = device("headset", connected: false)
        XCTAssertEqual(tracker.transitions(in: [disconnected], inventoryReady: true),
                       [.disconnected(disconnected)])
        XCTAssertTrue(tracker.transitions(in: [], inventoryReady: true).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [disconnected], inventoryReady: true).isEmpty)
    }

    func testNewDisconnectedDeviceDoesNotProduceAlert() {
        var tracker = ConnectionTransitionTracker()
        XCTAssertTrue(tracker.transitions(in: [], inventoryReady: true).isEmpty)
        XCTAssertTrue(tracker.transitions(in: [device("headset", connected: false)],
                                          inventoryReady: true).isEmpty)
    }

    func testLiveCallbacksAlertBeforeInventoryLoadsAndDoNotRepeat() {
        var tracker = ConnectionTransitionTracker()
        let connected = device("headset", connected: true)
        let disconnected = device("headset", connected: false)

        XCTAssertEqual(tracker.liveTransition(for: connected), .connected(connected))
        XCTAssertNil(tracker.liveTransition(for: connected))
        XCTAssertTrue(tracker.transitions(in: [connected], inventoryReady: true).isEmpty)
        XCTAssertEqual(tracker.liveTransition(for: disconnected), .disconnected(disconnected))
        XCTAssertNil(tracker.liveTransition(for: disconnected))
        XCTAssertTrue(tracker.transitions(in: [disconnected], inventoryReady: true).isEmpty)
    }

    func testMacBatteryDoesNotProduceConnectionAlert() {
        var tracker = ConnectionTransitionTracker()
        XCTAssertTrue(tracker.transitions(in: [], inventoryReady: true).isEmpty)

        let mac = Device(id: "mac", name: "This Mac", kind: .macBook,
                         source: .systemPower, isConnected: true)
        XCTAssertTrue(tracker.transitions(in: [mac], inventoryReady: true).isEmpty)
    }

    @MainActor
    func testBluetoothCallbackUpdatesConnectionWithoutOpeningDashboard() {
        let store = DeviceStore()
        let keyboard = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                              kind: .magicKeyboard, source: .systemProfiler, isConnected: false)
        store.applyInventory([keyboard])

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: true)
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.isConnected, true)
        store.applyInventory([keyboard]) // system_profiler may still report its earlier snapshot
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.isConnected, true)

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: false)
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.isConnected, false)
        var staleConnected = keyboard
        staleConnected.isConnected = true
        store.applyInventory([staleConnected])
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.isConnected, false)
    }

    @MainActor
    func testBluetoothCallbacksPresentAlertsWithoutInventoryOrDashboard() {
        let store = DeviceStore()
        let (settings, cleanupSettings) = alertBoxSettings()
        defer { cleanupSettings() }
        let presenter = AlertPresenter(settings: settings)
        let manager = ConnectionAlertManager(presenter: presenter)
        defer { presenter.dismiss(); presenter.dismiss() }
        var callbackStates: [Bool] = []
        let callbackSpy = store.connectionEvents.sink { callbackStates.append($0.isConnected) }
        defer { callbackSpy.cancel() }
        manager.start(store: store, settings: settings, alertsAllowedAt: .distantPast)

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: true)
        XCTAssertFalse(store.hasLoadedBluetoothInventory)
        let first = presenter.currentPanel
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.subtitle,
                       "Connected successfully")
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.deviceImageName,
                       "ConnectionKeyboard")
        XCTAssertEqual(first?.frame.height, 236)
        XCTAssertEqual(first?.isVisible, true)

        let batteryReading = Device(id: "bt-AA:BB:CC:DD:EE:FF", name: "MX Keys Mini",
                                    kind: .magicKeyboard, overallPercent: 15,
                                    source: .systemProfiler, isConnected: true)
        store.applyInventory([batteryReading])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.percent, 15)
        XCTAssertEqual(first?.frame.height, 284)
        XCTAssertEqual((first?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.recommendsCharging,
                       true)

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: false)
        XCTAssertEqual(callbackStates, [true, false])
        XCTAssertEqual(store.devices.first { $0.name == "MX Keys Mini" }?.isConnected, false)
        presenter.dismiss()
        let second = presenter.currentPanel
        XCTAssertEqual(second?.isVisible, true)
        XCTAssertEqual((second?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.subtitle,
                       "Disconnected")
        XCTAssertEqual((second?.contentView as? NSHostingView<CenteredAlertView>)?.rootView.alert.deviceImageName,
                       "ConnectionKeyboard")
        XCTAssertEqual(second?.frame.height, 236)
    }

    @MainActor
    func testStartupConnectionCallbacksStayQuietUntilOneMinuteAfterMonitoringStarts() {
        let store = DeviceStore()
        let (settings, cleanupSettings) = alertBoxSettings()
        defer { cleanupSettings() }
        let presenter = AlertPresenter(settings: settings)
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let manager = ConnectionAlertManager(presenter: presenter, now: { currentTime })
        defer { presenter.dismiss() }

        manager.start(store: store, settings: settings)
        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: true)
        XCTAssertNil(presenter.currentPanel, "Startup connections should not open an alert")

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: false)
        XCTAssertNil(presenter.currentPanel, "Startup disconnections should not open an alert")

        currentTime = currentTime.addingTimeInterval(60)
        XCTAssertNil(presenter.currentPanel, "Startup alerts must not be queued for later")

        store.processBluetoothEvent(address: "AA-BB-CC-DD-EE-FF", name: "MX Keys Mini", connected: true)
        XCTAssertEqual((presenter.currentPanel?.contentView as? NSHostingView<CenteredAlertView>)?
            .rootView.alert.subtitle, "Connected successfully")
    }

    @MainActor
    func testInventoryTransitionsAreQuietDuringStartupAndActiveAfterward() {
        let store = DeviceStore()
        let (settings, cleanupSettings) = alertBoxSettings()
        defer { cleanupSettings() }
        let presenter = AlertPresenter(settings: settings)
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let manager = ConnectionAlertManager(presenter: presenter, now: { currentTime })
        defer { presenter.dismiss() }

        manager.start(store: store, settings: settings)
        let connected = device("headset", connected: true)
        let disconnected = device("headset", connected: false)
        store.applyInventory([connected])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        store.applyInventory([disconnected])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(presenter.currentPanel)

        currentTime = currentTime.addingTimeInterval(60)
        store.applyInventory([connected])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual((presenter.currentPanel?.contentView as? NSHostingView<CenteredAlertView>)?
            .rootView.alert.subtitle, "Connected successfully")
    }

    private func alertBoxSettings() -> (AppSettings, () -> Void) {
        let suiteName = "ConnectionAlertTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.alertDisplayStyle = .alertBox
        return (settings, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
