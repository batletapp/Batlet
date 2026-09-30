import Foundation

enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case circular       // Existing persisted value for Batlet's popup style
    case notification   // standard macOS notification
    var id: String { rawValue }
    var label: String { self == .circular ? "Batlet Popup" : "Standard Notification" }
}

enum AlertSound: String, CaseIterable, Identifiable {
    case systemDefault, chime, bell, ripple, pulse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemDefault: return "System Default"
        case .chime: return "Chime"
        case .bell: return "Bell"
        case .ripple: return "Ripple"
        case .pulse: return "Pulse"
        }
    }

    var fileName: String? {
        switch self {
        case .systemDefault: return nil
        case .chime: return "AlertChime.wav"
        case .bell: return "AlertBell.wav"
        case .ripple: return "AlertRipple.wav"
        case .pulse: return "AlertPulse.wav"
        }
    }
}

/// A per-device battery alert configuration. A single alert may fire on low battery,
/// on fully charged, or both.
struct BatteryAlert: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Matches `Device.id` (the DeviceStore merge key).
    var deviceKey: String
    var deviceName: String
    var kind: DeviceKind

    var lowEnabled: Bool = true
    var lowThreshold: Int = 20
    var chargedEnabled: Bool = false

    var style: AlertStyle = .circular
    var playSound: Bool = true
    /// Optional for alerts saved before sound choices were added.
    var soundName: String? = nil

    var selectedSound: AlertSound {
        get { soundName.flatMap(AlertSound.init(rawValue:)) ?? .systemDefault }
        set { soundName = newValue == .systemDefault ? nil : newValue.rawValue }
    }
}
