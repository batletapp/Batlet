import Foundation

/// A coarse classification of a device, used to pick an icon and a display name.
enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case airpods
    case airpodsPro
    case airpodsMax
    case airpods3
    case airpodsPro2
    case airpods4
    case beats
    case headphones      // generic BLE earbuds / headset
    case mac             // desktop Mac
    case macBook         // portable Mac
    case iphone
    case ipad
    case watch
    case magicMouse
    case magicKeyboard
    case magicTrackpad
    case mouse
    case keyboard
    case trackpad
    case unknown

    var displayName: String {
        switch self {
        case .airpods: return "AirPods"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsMax: return "AirPods Max"
        case .airpods3: return "AirPods (3rd gen)"
        case .airpodsPro2: return "AirPods Pro (2nd gen)"
        case .airpods4: return "AirPods 4"
        case .beats: return "Beats"
        case .headphones: return "Headphones"
        case .mac: return "Mac"
        case .macBook: return "MacBook"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .watch: return "Apple Watch"
        case .magicMouse: return "Magic Mouse"
        case .magicKeyboard: return "Magic Keyboard"
        case .magicTrackpad: return "Magic Trackpad"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .trackpad: return "Trackpad"
        case .unknown: return "Bluetooth Device"
        }
    }

    /// SF Symbol used to represent the device in the Dashboard and Settings.
    var symbolName: String {
        switch self {
        case .airpods, .airpods3, .airpods4: return "airpods"
        case .airpodsPro, .airpodsPro2: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .headphones: return "headphones"
        case .mac: return "desktopcomputer"
        case .macBook: return "laptopcomputer"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .watch: return "applewatch"
        case .magicMouse: return "magicmouse"
        case .magicKeyboard: return "keyboard"
        case .magicTrackpad: return "trackpad"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "trackpad"
        case .unknown: return "dot.radiowaves.left.and.right"
        }
    }

    /// Local Tabler outline asset used for the device rows. Trackpads keep the
    /// native symbol because Tabler does not ship a dedicated trackpad glyph.
    var iconAssetName: String? {
        switch self {
        case .airpods, .airpodsPro, .airpods3, .airpodsPro2, .airpods4:
            return "TablerDeviceAirPods"
        case .airpodsMax, .beats, .headphones:
            return "TablerHeadphones"
        case .mac:
            return "TablerDeviceDesktop"
        case .macBook:
            return "TablerDeviceLaptop"
        case .iphone:
            return "TablerDeviceMobile"
        case .ipad:
            return "TablerDeviceIPad"
        case .watch:
            return "TablerDeviceWatch"
        case .magicMouse, .mouse:
            return "TablerMouse"
        case .magicKeyboard, .keyboard:
            return "TablerKeyboard"
        case .magicTrackpad, .trackpad, .unknown:
            return nil
        }
    }

    /// Whether this is an AirPods/Beats-style device with left/right/case components.
    var isAirPodsFamily: Bool {
        switch self {
        case .airpods, .airpodsPro, .airpodsMax, .airpods3, .airpodsPro2, .airpods4, .beats:
            return true
        case .headphones, .mac, .macBook, .iphone, .ipad, .watch,
             .magicMouse, .magicKeyboard, .magicTrackpad,
             .mouse, .keyboard, .trackpad, .unknown:
            return false
        }
    }

    /// A single-battery over-ear device (AirPods Max, most Beats) reports one level, no case.
    var isSingleBattery: Bool {
        switch self {
        case .airpodsMax: return true
        default: return false
        }
    }

    /// Best-effort mapping from the Continuity proximity-pairing model value.
    /// The model is two bytes; the discriminating byte is the low byte (the high byte is
    /// commonly 0x20). Unknown Apple audio models fall back to a generic AirPods icon.
    static func fromContinuityModel(_ model: UInt16) -> DeviceKind {
        switch model & 0x00FF {
        case 0x02: return .airpods       // AirPods (1st gen)
        case 0x0F: return .airpods       // AirPods (2nd gen)
        case 0x13: return .airpods3      // AirPods (3rd gen)
        case 0x19: return .airpods4      // AirPods 4
        case 0x1B: return .airpods4      // AirPods 4 (ANC)
        case 0x0E: return .airpodsPro    // AirPods Pro
        case 0x14: return .airpodsPro2   // AirPods Pro (2nd gen)
        case 0x24: return .airpodsPro2   // AirPods Pro (2nd gen, USB-C)
        case 0x0A: return .airpodsMax
        case 0x1F: return .airpodsMax    // AirPods Max (USB-C)
        case 0x05, 0x06, 0x09, 0x0B, 0x0C, 0x10, 0x11, 0x17, 0x12, 0x1A:
            return .beats
        default:
            return .airpods
        }
    }
}
