import Foundation
import CoreBluetooth
import UserNotifications
import AppKit

/// Tracks and requests the permissions Batlet needs: Bluetooth (required) and
/// Notifications (recommended, for standard-style battery alerts).
@MainActor
final class PermissionsManager: NSObject, ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var bluetooth: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var notifications: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationAlertsEnabled: Bool?

    private var central: CBCentralManager?

    override init() {
        super.init()
        refresh()
    }

    var bluetoothGranted: Bool { bluetooth == .allowedAlways }

    /// Instantiating a CBCentralManager triggers the system Bluetooth permission prompt
    /// on first use. There is no API to re-prompt once denied; the UI then links to Settings.
    func requestBluetooth() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        bluetooth = CBManager.authorization
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshNotifications() }
        }
    }

    func refresh() {
        bluetooth = CBManager.authorization
        refreshNotifications()
    }

    private func refreshNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.notifications = settings.authorizationStatus
                self?.notificationAlertsEnabled = settings.alertSetting == .enabled
            }
        }
    }

    /// Opens System Settings to the relevant privacy pane.
    static func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension PermissionsManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let auth = CBManager.authorization
        Task { @MainActor in self.bluetooth = auth }
    }
}
