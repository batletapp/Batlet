import Foundation

/// Source used to identify and track a device; battery readings may use another source.
enum DeviceSource: String, Codable, Sendable {
    case continuityBLE   // Apple Continuity proximity-pairing advertisement (AirPods/Beats)
    case gattBLE         // Standard GATT Battery Service (0x180F)
    case systemPower     // IOKit power sources (this Mac)
    case systemProfiler  // system_profiler / IORegistry (Magic peripherals, classic BT)
    case mobileDevice    // Trusted iPhone or iPad over USB / Wi-Fi
}

/// Source of a battery reading, independent of the source used for device identity.
enum BatteryReadingSource: Int, Sendable {
    case continuityBLE = 1
    case systemProfiler = 2
    case gattBLE = 3
    case accessoryPower = 4
    case mobileDevice = 5
    case systemPower = 6

    init(deviceSource: DeviceSource) {
        switch deviceSource {
        case .continuityBLE: self = .continuityBLE
        case .systemProfiler: self = .systemProfiler
        case .gattBLE: self = .gattBLE
        case .mobileDevice: self = .mobileDevice
        case .systemPower: self = .systemPower
        }
    }
}

/// A device shown in the Dashboard. `id` is a stable identifier where possible
/// (BLE peripheral identifier, IORegistry address, or a name-based fallback).
struct Device: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: DeviceKind

    /// Overall level shown on the row (for AirPods, the lower of the two buds).
    var overallPercent: Int?
    var batteryReadingSource: BatteryReadingSource?
    var isCharging: Bool
    /// External power is connected, even if charging is paused or complete.
    var isConnectedToPower: Bool

    // AirPods-family components (nil for simple single-battery devices).
    var left: BatteryComponent?
    var right: BatteryComponent?
    var caseComponent: BatteryComponent?

    var rssi: Int?
    var lastSeen: Date
    var source: DeviceSource
    var isConnected: Bool

    // User preferences (persisted separately, mirrored here for display).
    var isPinned: Bool
    var isFavorite: Bool

    init(
        id: String,
        name: String,
        kind: DeviceKind,
        overallPercent: Int? = nil,
        batteryReadingSource: BatteryReadingSource? = nil,
        isCharging: Bool = false,
        isConnectedToPower: Bool = false,
        left: BatteryComponent? = nil,
        right: BatteryComponent? = nil,
        caseComponent: BatteryComponent? = nil,
        rssi: Int? = nil,
        lastSeen: Date = Date(),
        source: DeviceSource,
        isConnected: Bool = false,
        isPinned: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.overallPercent = overallPercent
        self.batteryReadingSource = overallPercent == nil ? nil
            : (batteryReadingSource ?? BatteryReadingSource(deviceSource: source))
        self.isCharging = isCharging
        self.isConnectedToPower = isConnectedToPower
        self.left = left
        self.right = right
        self.caseComponent = caseComponent
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.source = source
        self.isConnected = isConnected
        self.isPinned = isPinned
        self.isFavorite = isFavorite
    }
}

extension Device {
    /// Builds a Device from a decoded Continuity advertisement.
    static func from(advertisement a: AirPodsAdvertisement, id: String, name: String? = nil, rssi: Int? = nil) -> Device {
        let overall: Int?
        if a.kind.isSingleBattery {
            overall = a.left?.percent ?? a.right?.percent
        } else {
            let levels = [a.left?.percent, a.right?.percent].compactMap { $0 }
            overall = levels.min()
        }
        let charging = (a.left?.isCharging ?? false) || (a.right?.isCharging ?? false)
        return Device(
            id: id,
            name: name ?? a.kind.displayName,
            kind: a.kind,
            overallPercent: overall,
            isCharging: charging,
            left: a.left,
            right: a.right,
            caseComponent: a.caseComponent,
            rssi: rssi,
            lastSeen: Date(),
            source: .continuityBLE,
            isConnected: false
        )
    }
}
