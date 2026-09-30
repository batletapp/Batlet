import Foundation
import Combine
import AppKit
import UserNotifications

struct BatteryNotificationSettings {
    let authorizationStatus: UNAuthorizationStatus
    let alertsEnabled: Bool
    let soundsEnabled: Bool
}

@MainActor
protocol BatteryNotificationClient {
    func settings() async -> BatteryNotificationSettings
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
}

@MainActor
private struct SystemBatteryNotificationClient: BatteryNotificationClient {
    private let center = UNUserNotificationCenter.current()

    func settings() async -> BatteryNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: BatteryNotificationSettings(
                    authorizationStatus: settings.authorizationStatus,
                    alertsEnabled: settings.alertSetting == .enabled,
                    soundsEnabled: settings.soundSetting == .enabled
                ))
            }
        }
    }

    func requestAuthorization() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        PermissionsManager.shared.refresh()
        return granted
    }

    func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        center.add(request, withCompletionHandler: completion)
    }
}

enum BatteryPreviewResult: Equatable {
    case popupShown
    case notificationSent
    case appNotificationsDisabled
    case soundDisabled
    case permissionDenied
    case alertsDisabled
    case deliveryFailed

    var message: String? {
        switch self {
        case .popupShown: return nil
        case .notificationSent: return "Sent to macOS. Focus or notification settings may delay the banner."
        case .appNotificationsDisabled: return "Turn on System notifications in Batlet Settings to send this preview."
        case .soundDisabled: return "Notification sent, but Batlet sounds are off in System Settings."
        case .permissionDenied: return "Notifications are off for Batlet in System Settings."
        case .alertsDisabled: return "Notification banners are off for Batlet in System Settings."
        case .deliveryFailed: return "The notification preview could not be sent."
        }
    }

    var needsSystemSettings: Bool {
        switch self {
        case .soundDisabled, .permissionDenied, .alertsDisabled: return true
        default: return false
        }
    }
}

/// Evaluates configured battery alerts against live device readings and delivers them,
/// edge-triggered so an alert fires once per crossing (not repeatedly).
@MainActor
final class BatteryAlertManager: ObservableObject {
    static let shared = BatteryAlertManager()

    private let presenter = AlertPresenter.shared
    private let notificationClient: any BatteryNotificationClient
    private var cancellables = Set<AnyCancellable>()
    private var settings: AppSettings

    init(notificationClient: (any BatteryNotificationClient)? = nil,
         settings: AppSettings = .shared) {
        self.notificationClient = notificationClient ?? SystemBatteryNotificationClient()
        self.settings = settings
    }

    // Device keys currently in the "fired" state, to avoid repeat alerts.
    private var firedLow: Set<String> = []
    private var firedCharged: Set<String> = []

    func start(store: DeviceStore, settings: AppSettings) {
        self.settings = settings
        store.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in self?.evaluate(devices) }
            .store(in: &cancellables)
    }

    private func evaluate(_ devices: [Device]) {
        for alert in settings.batteryAlerts {
            guard let device = devices.first(where: { $0.id == alert.deviceKey }),
                  let percent = device.overallPercent else { continue }

            if alert.lowEnabled {
                let inLow = percent <= alert.lowThreshold && !device.isCharging
                if inLow, !firedLow.contains(alert.deviceKey) {
                    firedLow.insert(alert.deviceKey)
                    deliver(alert: alert, device: device, percent: percent, charged: false)
                } else if !inLow, percent > alert.lowThreshold + 5 || device.isCharging {
                    firedLow.remove(alert.deviceKey)
                }
            }

            if alert.chargedEnabled {
                if percent >= 100, !firedCharged.contains(alert.deviceKey) {
                    firedCharged.insert(alert.deviceKey)
                    deliver(alert: alert, device: device, percent: percent, charged: true)
                } else if percent < 95 {
                    firedCharged.remove(alert.deviceKey)
                }
            }
        }
    }

    private func deliver(alert: BatteryAlert, device: Device, percent: Int, charged: Bool) {
        let subtitle = charged ? "Fully Charged" : "Battery Low"
        switch alert.style {
        case .circular:
            presenter.show(AlertPresentation(
                title: alert.deviceName, subtitle: subtitle,
                symbol: device.kind.symbolName, percent: percent,
                tone: charged ? .success : .warning
            ))
        case .notification:
            guard settings.systemNotificationsEnabled else { return }
            postNotification(title: alert.deviceName, body: "\(subtitle) • \(percent)%",
                             sound: alert.playSound ? alert.selectedSound : nil)
        }
        if alert.playSound, alert.style == .circular {
            AlertSoundPlayer.shared.play(alert.selectedSound)
        }
    }

    private func postNotification(title: String, body: String, sound: AlertSound?) {
        notificationClient.add(Self.notificationRequest(title: title, body: body, sound: sound)) { _ in }
    }

    private static func notificationRequest(title: String, body: String,
                                            sound: AlertSound?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let sound {
            if let fileName = sound.fileName, AlertSoundPlayer.url(for: fileName) != nil {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
            } else {
                content.sound = .default
            }
        }
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    /// Fires a one-off preview alert (used by the configuration sheet).
    func preview(kind: DeviceKind, name: String, threshold: Int, style: AlertStyle,
                 playSound: Bool, sound: AlertSound = .systemDefault) async -> BatteryPreviewResult {
        switch style {
        case .circular:
            presenter.show(AlertPresentation(
                title: name, subtitle: "Battery Low", symbol: kind.symbolName,
                percent: threshold, tone: .warning
            ))
            if playSound { AlertSoundPlayer.shared.play(sound) }
            return .popupShown
        case .notification:
            guard settings.systemNotificationsEnabled else { return .appNotificationsDisabled }
            var currentSettings = await notificationClient.settings()
            var justAuthorized = false
            if currentSettings.authorizationStatus == .notDetermined {
                guard await notificationClient.requestAuthorization() else { return .permissionDenied }
                justAuthorized = true
                currentSettings = await notificationClient.settings()
            }
            guard currentSettings.authorizationStatus != .denied else { return .permissionDenied }
            guard currentSettings.alertsEnabled || justAuthorized else { return .alertsDisabled }

            let request = Self.notificationRequest(
                title: name, body: "Battery Low • \(threshold)%",
                sound: playSound ? sound : nil
            )
            let error = await withCheckedContinuation { continuation in
                notificationClient.add(request) { continuation.resume(returning: $0) }
            }
            guard error == nil else { return .deliveryFailed }
            if playSound && !justAuthorized && !currentSettings.soundsEnabled {
                return .soundDisabled
            }
            return .notificationSent
        }
    }
}
