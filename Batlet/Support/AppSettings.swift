import Foundation
import Combine

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case appIcon, bolt, sparkle, headphones, plug
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appIcon: return "Batlet"
        case .bolt: return "Bolt"
        case .sparkle: return "Sparkle"
        case .headphones: return "Headphones"
        case .plug: return "Plug"
        }
    }

    var symbolName: String {
        switch self {
        case .appIcon: return "bolt.circle.fill"
        case .bolt: return "bolt.fill"
        case .sparkle: return "sparkle"
        case .headphones: return "headphones"
        case .plug: return "powerplug.fill"
        }
    }
}

enum BatteryDisplayType: String, CaseIterable, Identifiable {
    case circle, bar

    var id: String { rawValue }
    var label: String { self == .circle ? "Circle" : "Bar" }
}

enum AlertDisplayStyle: String, CaseIterable, Identifiable {
    case alertBox, hub

    var id: String { rawValue }
    var label: String { self == .alertBox ? "Alert Box" : "Hub" }
}

enum HubVerticalPosition: String, CaseIterable, Identifiable {
    case top, bottom

    var id: String { rawValue }
    var label: String { self == .top ? "Top" : "Bottom" }
}

enum HubHorizontalAlignment: String, CaseIterable, Identifiable {
    case left, center, right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// App-wide preferences, persisted to `UserDefaults` and observed by the UI.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private var isLoading = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLoading = true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        menuBarIconStyle = MenuBarIconStyle(rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "") ?? .appIcon
        showMenuBarBadgeCount = defaults.object(forKey: Keys.showMenuBarBadgeCount) as? Bool ?? true
        batteryDisplayType = BatteryDisplayType(rawValue: defaults.string(forKey: Keys.batteryDisplayType) ?? "") ?? .bar
        alertDisplayStyle = AlertDisplayStyle(rawValue: defaults.string(forKey: Keys.alertDisplayStyle) ?? "") ?? .alertBox
        hubVerticalPosition = HubVerticalPosition(rawValue: defaults.string(forKey: Keys.hubVerticalPosition) ?? "") ?? .top
        hubHorizontalAlignment = HubHorizontalAlignment(rawValue: defaults.string(forKey: Keys.hubHorizontalAlignment) ?? "") ?? .center
        systemNotificationsEnabled = defaults.object(forKey: Keys.systemNotificationsEnabled) as? Bool ?? true
        automaticUpdateChecksEnabled = defaults.object(forKey: Keys.automaticUpdateChecksEnabled) as? Bool ?? false
        nearbyPromptsEnabled = defaults.object(forKey: Keys.nearbyPromptsEnabled) as? Bool ?? false
        favoriteDeviceID = defaults.string(forKey: Keys.favoriteDeviceID)
        pinnedDeviceIDs = Set(defaults.stringArray(forKey: Keys.pinnedDeviceIDs) ?? [])
        hiddenDeviceIDs = Set(defaults.stringArray(forKey: Keys.hiddenDeviceIDs) ?? [])
        customNames = defaults.dictionary(forKey: Keys.customNames) as? [String: String] ?? [:]
        if let data = defaults.data(forKey: Keys.batteryAlerts),
           let decoded = try? JSONDecoder().decode([BatteryAlert].self, from: data) {
            batteryAlerts = decoded
        } else {
            batteryAlerts = []
        }
        isLoading = false
    }

    @Published var hasCompletedOnboarding: Bool { didSet { persist(hasCompletedOnboarding, Keys.hasCompletedOnboarding) } }
    @Published var menuBarIconStyle: MenuBarIconStyle { didSet { persist(menuBarIconStyle.rawValue, Keys.menuBarIconStyle) } }
    @Published var showMenuBarBadgeCount: Bool { didSet { persist(showMenuBarBadgeCount, Keys.showMenuBarBadgeCount) } }
    @Published var batteryDisplayType: BatteryDisplayType { didSet { persist(batteryDisplayType.rawValue, Keys.batteryDisplayType) } }
    @Published var alertDisplayStyle: AlertDisplayStyle { didSet { persist(alertDisplayStyle.rawValue, Keys.alertDisplayStyle) } }
    @Published var hubVerticalPosition: HubVerticalPosition { didSet { persist(hubVerticalPosition.rawValue, Keys.hubVerticalPosition) } }
    @Published var hubHorizontalAlignment: HubHorizontalAlignment { didSet { persist(hubHorizontalAlignment.rawValue, Keys.hubHorizontalAlignment) } }
    @Published var systemNotificationsEnabled: Bool { didSet { persist(systemNotificationsEnabled, Keys.systemNotificationsEnabled) } }
    @Published var automaticUpdateChecksEnabled: Bool { didSet { persist(automaticUpdateChecksEnabled, Keys.automaticUpdateChecksEnabled) } }
    @Published var nearbyPromptsEnabled: Bool { didSet { persist(nearbyPromptsEnabled, Keys.nearbyPromptsEnabled) } }
    @Published var favoriteDeviceID: String? { didSet { persist(favoriteDeviceID, Keys.favoriteDeviceID) } }
    @Published var pinnedDeviceIDs: Set<String> { didSet { persist(Array(pinnedDeviceIDs), Keys.pinnedDeviceIDs) } }
    @Published var hiddenDeviceIDs: Set<String> { didSet { persist(Array(hiddenDeviceIDs), Keys.hiddenDeviceIDs) } }
    @Published var customNames: [String: String] { didSet { persist(customNames, Keys.customNames) } }
    @Published var batteryAlerts: [BatteryAlert] { didSet { persistAlerts() } }

    // MARK: - Convenience

    func alert(for deviceID: String) -> BatteryAlert? {
        batteryAlerts.first { $0.deviceKey == deviceID }
    }

    func upsert(_ alert: BatteryAlert) {
        if let index = batteryAlerts.firstIndex(where: { $0.deviceKey == alert.deviceKey }) {
            batteryAlerts[index] = alert
        } else {
            batteryAlerts.append(alert)
        }
    }

    func removeAlert(for deviceID: String) {
        batteryAlerts.removeAll { $0.deviceKey == deviceID }
    }

    private func persistAlerts() {
        guard !isLoading else { return }
        defaults.set(try? JSONEncoder().encode(batteryAlerts), forKey: Keys.batteryAlerts)
    }

    func displayName(for device: Device) -> String {
        customNames[device.id] ?? device.name
    }

    /// Matches the connected rows in the dashboard, including pinned devices.
    func visibleConnectedDeviceCount(in devices: [Device]) -> Int {
        devices.filter { $0.isConnected && !hiddenDeviceIDs.contains($0.id) }.count
    }

    func menuBarBadgeCount(in devices: [Device]) -> Int {
        showMenuBarBadgeCount ? visibleConnectedDeviceCount(in: devices) : 0
    }

    func togglePinned(_ id: String) {
        if pinnedDeviceIDs.contains(id) { pinnedDeviceIDs.remove(id) } else { pinnedDeviceIDs.insert(id) }
    }

    func toggleHidden(_ id: String) {
        if hiddenDeviceIDs.contains(id) { hiddenDeviceIDs.remove(id) } else { hiddenDeviceIDs.insert(id) }
    }

    private func persist(_ value: Any?, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let showMenuBarBadgeCount = "showMenuBarBadgeCount"
        static let batteryDisplayType = "batteryDisplayType"
        static let alertDisplayStyle = "alertDisplayStyle"
        static let hubVerticalPosition = "hubVerticalPosition"
        static let hubHorizontalAlignment = "hubHorizontalAlignment"
        static let systemNotificationsEnabled = "systemNotificationsEnabled"
        static let automaticUpdateChecksEnabled = "automaticUpdateChecksEnabled"
        static let nearbyPromptsEnabled = "nearbyPromptsEnabled"
        static let favoriteDeviceID = "favoriteDeviceID"
        static let pinnedDeviceIDs = "pinnedDeviceIDs"
        static let hiddenDeviceIDs = "hiddenDeviceIDs"
        static let customNames = "customNames"
        static let batteryAlerts = "batteryAlerts"
    }
}
