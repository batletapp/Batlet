import AppKit
import IOBluetooth
import SwiftUI
import XCTest
@testable import Batlet

final class NearbyPromptTests: XCTestCase {
    func testConnectionAttemptWaitsForSystemEventAndHandlesLateSuccess() {
        var tracker = NearbyConnectionTracker()
        XCTAssertTrue(tracker.begin("bt-ew02"))
        XCTAssertEqual(tracker.state(for: "bt-ew02"), .connecting)
        XCTAssertFalse(tracker.begin("bt-ew02"))

        // A low-level connection result must not end the UI attempt early.
        XCTAssertEqual(tracker.state(for: "bt-ew02"), .connecting)
        XCTAssertTrue(tracker.systemConnected("bt-ew02"))
        XCTAssertEqual(tracker.state(for: "bt-ew02"), .connected)
        XCTAssertFalse(tracker.timeout("bt-ew02"))

        XCTAssertTrue(tracker.begin("bt-mouse"))
        XCTAssertTrue(tracker.timeout("bt-mouse"))
        XCTAssertEqual(tracker.state(for: "bt-mouse"), .failed)
        XCTAssertTrue(tracker.systemConnected("bt-mouse"))
        XCTAssertEqual(tracker.state(for: "bt-mouse"), .connected)
    }

    func testManualResultsChooseDirectConnectOrBluetoothSettings() {
        let direct = NearbyDeviceCandidate(id: "bt-0011", name: "EW02", kind: .headphones,
                                           address: "00:11", isPaired: false, batteryPercent: nil)
        let bleOnly = NearbyDeviceCandidate(id: "ble-mouse", name: "Travel Mouse", kind: .mouse,
                                            address: nil, isPaired: false, batteryPercent: nil)
        XCTAssertEqual(direct.actionTitle, "Connect")
        XCTAssertEqual(bleOnly.actionTitle, "Open Settings")
    }

    func testUnpairedClassicAudioDeviceCanBeSuggested() {
        XCTAssertTrue(NearbyPromptPolicy.supports(.headphones, isPaired: false))
    }

    func testEW02IsAudioWhenClassicInquiryReportsAudioClass() {
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "EW02", knownKind: nil,
                                              classicMajorClass: BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)),
                       .headphones)
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "OPPO A52", knownKind: nil,
                                              classicMajorClass: BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone)),
                       .unknown)
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "Generic Pointer", knownKind: nil,
                                              classicMajorClass: BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral),
                                              classicMinorClass: 0x20),
                       .mouse)
    }

    func testTVIsExcludedEvenWhenBluetoothReportsAudioClass() {
        let audio = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
        let display = BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVideoDisplayAndLoudspeaker)

        XCTAssertEqual(NearbyPromptPolicy.kind(name: "[LG] webOS SR83U", knownKind: nil,
                                              classicMajorClass: audio, classicMinorClass: display),
                       .unknown)
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "[LG] webOS SR83U", knownKind: nil,
                                              classicMajorClass: audio),
                       .unknown)
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "Living Room TV", knownKind: .headphones,
                                              classicMajorClass: audio),
                       .unknown)
        XCTAssertEqual(NearbyPromptPolicy.kind(name: "EW02", knownKind: nil,
                                              classicMajorClass: audio,
                                              classicMinorClass: BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHeadphones)),
                       .headphones)
    }

    @MainActor
    func testInquiryAndPairingCallbacksAreExposedToBluetoothFramework() {
        let manager = NearbyDeviceManager.shared
        XCTAssertTrue(manager.responds(to: NSSelectorFromString("deviceInquiryDeviceNameUpdated:device:devicesRemaining:")))
        XCTAssertTrue(manager.responds(to: NSSelectorFromString("devicePairingFinished:error:")))
        XCTAssertTrue(manager.responds(to: NSSelectorFromString("devicePairingUserConfirmationRequest:numericValue:")))
        XCTAssertTrue(manager.responds(to: NSSelectorFromString("devicePairingPINCodeRequest:")))
    }

    func testBLERequiresTwoRecentSightingsAndRespectsCooldown() {
        var gate = NearbyPromptGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(gate.shouldPrompt(address: "aabb", at: start,
                                         needsSecondSighting: true))
        XCTAssertFalse(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(16),
                                         needsSecondSighting: true))
        XCTAssertTrue(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(17),
                                        needsSecondSighting: true))
        XCTAssertFalse(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(18),
                                         needsSecondSighting: true))
        XCTAssertFalse(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(3_618),
                                         needsSecondSighting: true))
        XCTAssertTrue(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(3_619),
                                        needsSecondSighting: true))
    }

    func testClassicSightingCanPromptImmediatelyButNotRepeat() {
        var gate = NearbyPromptGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.shouldPrompt(address: "aabb", at: start,
                                        needsSecondSighting: false))
        XCTAssertFalse(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(180),
                                         needsSecondSighting: false))
        XCTAssertTrue(gate.shouldPrompt(address: "ccdd", at: start.addingTimeInterval(180),
                                        needsSecondSighting: false))
        XCTAssertTrue(gate.shouldPrompt(address: "aabb", at: start.addingTimeInterval(3_600),
                                        needsSecondSighting: false))
    }

    @MainActor
    func testNearbyPromptOffersConnectAndCanBeRemovedWhenDeviceConnects() {
        let suiteName = "NearbyPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.alertDisplayStyle = .alertBox
        let presenter = AlertPresenter(settings: settings)
        defer { presenter.dismiss() }
        var didConnect = false
        presenter.show(AlertPresentation(
            title: "Travel Mouse", subtitle: "Nearby and ready to connect",
            symbol: "computermouse", percent: nil, tone: .neutral,
            autoDismiss: 30, isConnectionEvent: true,
            nearbyDeviceAddress: "aabb",
            primaryAction: { didConnect = true }
        ))

        let first = presenter.currentPanel
        XCTAssertEqual(first?.frame.height, 278)
        let view = first?.contentView as? NSHostingView<CenteredAlertView>
        XCTAssertNotNil(view?.rootView.onPrimaryAction)
        view?.rootView.onPrimaryAction?()
        XCTAssertTrue(didConnect)
        XCTAssertNil(presenter.currentPanel)

        presenter.show(AlertPresentation(
            title: "Travel Mouse", subtitle: "Nearby and ready to connect",
            symbol: "computermouse", percent: nil, tone: .neutral,
            autoDismiss: 30, isConnectionEvent: true,
            nearbyDeviceAddress: "aabb", primaryAction: {}
        ))
        presenter.removeNearbyPrompt(for: "aabb")
        XCTAssertNil(presenter.currentPanel)
    }
}
