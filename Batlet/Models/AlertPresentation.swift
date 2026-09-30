import Foundation

/// Content for Batlet's reusable centered popup. Event detection stays with the
/// caller; the presenter only manages display, dismissal, and queued alerts.
struct AlertPresentation {
    enum BatteryLevel: Equatable {
        case healthy
        case low
        case critical

        init(percent: Int) {
            if percent > 20 { self = .healthy }
            else if percent >= 10 { self = .low }
            else { self = .critical }
        }
    }

    enum Tone {
        case success
        case warning
        case neutral
    }

    let title: String
    let subtitle: String
    let symbol: String
    var percent: Int?
    let tone: Tone
    var autoDismiss: TimeInterval = 6
    var connectionDeviceID: String? = nil
    var isCharging = false
    var deviceImageName: String? = nil
    var isConnectionEvent = false
    var nearbyDeviceAddress: String? = nil
    var primaryAction: (() -> Void)? = nil
    var expiresAt: Date? = nil

    var batteryLevel: BatteryLevel? { percent.map(BatteryLevel.init(percent:)) }
    var recommendsCharging: Bool {
        connectionDeviceID != nil && !isCharging && (percent.map { $0 < 20 } ?? false)
    }
}
