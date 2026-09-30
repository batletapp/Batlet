import Foundation
import Combine

/// Recognizes real connection changes after the first Bluetooth inventory has loaded.
/// Missing devices retain their last state; a transiently empty inventory must not make
/// every connected device look newly connected on the next refresh.
enum ConnectionTransition: Equatable {
    case connected(Device)
    case disconnected(Device)
}

struct ConnectionTransitionTracker {
    private var hasBaseline = false
    private var connectionByID: [String: Bool] = [:]

    mutating func transitions(in devices: [Device], inventoryReady: Bool) -> [ConnectionTransition] {
        guard inventoryReady else { return [] }
        let bluetoothDevices = devices.filter { $0.source != .systemPower }

        if !hasBaseline {
            hasBaseline = true
            for device in bluetoothDevices { connectionByID[device.id] = device.isConnected }
            return []
        }

        let changes: [ConnectionTransition] = bluetoothDevices.compactMap { device in
            let previous = connectionByID[device.id]
            if device.isConnected && previous != true { return .connected(device) }
            if !device.isConnected && previous == true { return .disconnected(device) }
            return nil
        }
        for device in bluetoothDevices { connectionByID[device.id] = device.isConnected }
        return changes
    }

    mutating func liveTransition(for device: Device) -> ConnectionTransition? {
        guard device.source != .systemPower else { return nil }
        let previous = connectionByID[device.id]
        connectionByID[device.id] = device.isConnected
        if device.isConnected, previous != true { return .connected(device) }
        if !device.isConnected, previous != false { return .disconnected(device) }
        return nil
    }
}

@MainActor
final class ConnectionAlertManager {
    static let shared = ConnectionAlertManager()

    private let presenter: AlertPresenter
    private let now: () -> Date
    private var tracker = ConnectionTransitionTracker()
    private var alertsAllowedAt: Date = .distantFuture
    private var subscription: AnyCancellable?
    private var liveSubscription: AnyCancellable?

    convenience init() {
        self.init(presenter: .shared)
    }

    init(presenter: AlertPresenter, now: @escaping () -> Date = Date.init) {
        self.presenter = presenter
        self.now = now
    }

    func start(store: DeviceStore, settings: AppSettings, alertsAllowedAt: Date? = nil) {
        guard subscription == nil else { return }
        self.alertsAllowedAt = alertsAllowedAt ?? now().addingTimeInterval(60)
        liveSubscription = store.connectionEvents
            .sink { [weak self] device in
                guard let self, let transition = self.tracker.liveTransition(for: device) else { return }
                if self.now() >= self.alertsAllowedAt {
                    self.present(transition, settings: settings)
                }
            }
        subscription = store.$devices
            .combineLatest(store.$hasLoadedBluetoothInventory)
            .receive(on: RunLoop.main)
            .sink { [weak self] devices, inventoryReady in
                guard let self else { return }
                let transitions = self.tracker.transitions(
                    in: devices, inventoryReady: inventoryReady
                )
                if self.now() >= self.alertsAllowedAt {
                    for transition in transitions {
                        self.present(transition, settings: settings)
                    }
                }
                for device in devices where device.isConnected {
                    if let percent = device.overallPercent {
                        self.presenter.updateConnectionBattery(
                            for: device.id, percent: percent, isCharging: device.isCharging
                        )
                    }
                }
            }
    }

    private func present(_ transition: ConnectionTransition, settings: AppSettings) {
        let device: Device
        let subtitle: String
        let tone: AlertPresentation.Tone
        let percent: Int?
        let connectionDeviceID: String?
        let isCharging: Bool
        switch transition {
        case .connected(let connected):
            device = connected
            subtitle = "Connected successfully"
            tone = .success
            percent = connected.overallPercent
            connectionDeviceID = connected.id
            isCharging = connected.isCharging
        case .disconnected(let disconnected):
            device = disconnected
            subtitle = "Disconnected"
            tone = .neutral
            percent = nil
            connectionDeviceID = nil
            isCharging = false
        }
        presenter.show(AlertPresentation(
            title: settings.displayName(for: device),
            subtitle: subtitle,
            symbol: device.kind.symbolName,
            percent: percent,
            tone: tone,
            connectionDeviceID: connectionDeviceID,
            isCharging: isCharging,
            deviceImageName: ConnectionPopupImage.assetName(for: device.kind),
            isConnectionEvent: true
        ))
    }
}

/// Product cutouts are used only by connection popups; other UI keeps its SF Symbols.
enum ConnectionPopupImage {
    static func assetName(for kind: DeviceKind) -> String? {
        switch kind {
        case .airpods, .airpodsPro, .airpodsMax, .airpods3, .airpodsPro2, .airpods4:
            return "ConnectionAirPods"
        case .beats, .headphones:
            return "ConnectionHeadphones"
        case .magicMouse:
            return "ConnectionMagicMouse"
        case .mouse:
            return "ConnectionMouse"
        case .magicKeyboard, .keyboard:
            return "ConnectionKeyboard"
        case .magicTrackpad, .trackpad:
            return "ConnectionTrackpad"
        case .iphone:
            return "ConnectionIPhone"
        case .ipad:
            return "ConnectionIPad"
        case .watch:
            return "ConnectionWatch"
        case .mac, .macBook, .unknown:
            return nil
        }
    }
}
