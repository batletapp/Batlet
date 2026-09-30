import Foundation
import Darwin
import CryptoKit

/// Reads battery levels from iPhones and iPads that have already trusted this Mac.
/// MobileDevice is a macOS private framework; keep its symbols behind a runtime lookup
/// so the rest of Batlet continues to work if an OS update changes the interface.
final class MobileDeviceSource {
    var onDevicesChanged: (([Device]) -> Void)?

    private static var active: MobileDeviceSource?
    private static let notificationCallback: MobileDeviceAPI.NotificationCallback = { info, _ in
        guard let info else { return }
        let device = info.load(as: UnsafeMutableRawPointer?.self)
        let message = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size,
                                as: UInt32.self)
        active?.receive(message: message, device: device)
    }

    private let queue = DispatchQueue(label: "com.batlet.mobile-device")
    private let api: MobileDeviceAPI?
    private var notification: UnsafeMutableRawPointer?
    private var connections: [String: [UInt32: UnsafeMutableRawPointer]] = [:]
    private var started = false

    init() {
        api = MobileDeviceAPI()
    }

    func start() {
        guard !started, let api else { return }
        started = true
        Self.active = self

        // The Wi-Fi option also includes USB devices. Pairing is deliberately never
        // initiated here; the user must first choose Trust on their iPhone or iPad.
        let options = ["NotificationOptionSearchForWiFiPairableDevices": true] as NSDictionary
        let result = api.subscribe(Self.notificationCallback, 0, 0, nil, &notification,
                                   Unmanaged.passUnretained(options).toOpaque())
        if result != 0 {
            started = false
            Self.active = nil
            NSLog("Batlet: mobile device subscription unavailable (%d)", result)
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.readConnectedDevices() }
    }

    private func receive(message: UInt32, device: UnsafeMutableRawPointer?) {
        guard let api, let device else { return }
        api.retain(device)
        queue.async { [weak self] in
            guard let self else {
                api.release(device)
                return
            }
            guard let identifier = api.identifier(for: device), !identifier.isEmpty else {
                api.release(device)
                return
            }
            let connectionID = api.connectionID(device)
            switch message {
            case 1: // Connected, by USB or Wi-Fi.
                var byConnection = self.connections[identifier] ?? [:]
                if let old = byConnection.updateValue(device, forKey: connectionID) {
                    api.release(old)
                }
                self.connections[identifier] = byConnection
                self.readConnectedDevices()
            case 2: // Disconnected.
                if var byConnection = self.connections[identifier] {
                    if let old = byConnection.removeValue(forKey: connectionID) {
                        api.release(old)
                    }
                    self.connections[identifier] = byConnection.isEmpty ? nil : byConnection
                }
                api.release(device)
                self.readConnectedDevices()
            default:
                api.release(device)
            }
        }
    }

    private func readConnectedDevices() {
        guard let api else { return }
        var devices: [Device] = []
        for (identifier, byConnection) in connections {
            for device in byConnection.values {
                if let reading = api.read(device: device, identifier: identifier) {
                    devices.append(reading)
                    break
                }
            }
        }
        DispatchQueue.main.async { [weak self] in self?.onDevicesChanged?(devices) }
    }
}

private final class MobileDeviceAPI {
    typealias NotificationCallback = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    typealias Subscribe = @convention(c) (NotificationCallback, UInt32, UInt32,
                                          UnsafeMutableRawPointer?,
                                          UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                          UnsafeRawPointer?) -> Int32
    typealias DeviceOperation = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias DeviceReference = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias ConnectionID = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    typealias CopyIdentifier = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias CopyValue = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                         UnsafeRawPointer?) -> UnsafeMutableRawPointer?

    let subscribe: Subscribe
    let retain: DeviceReference
    let release: DeviceReference
    let connectionID: ConnectionID
    private let connect: DeviceOperation
    private let isPaired: DeviceOperation
    private let validatePairing: DeviceOperation
    private let startSession: DeviceOperation
    private let stopSession: DeviceOperation
    private let disconnect: DeviceOperation
    private let copyIdentifier: CopyIdentifier
    private let copyValue: CopyValue
    private let framework: UnsafeMutableRawPointer

    init?() {
        guard let framework = dlopen(
            "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW
        ) else { return nil }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(framework, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }

        guard let subscribe = symbol("AMDeviceNotificationSubscribeWithOptions", as: Subscribe.self),
              let retain = symbol("AMDeviceRetain", as: DeviceReference.self),
              let release = symbol("AMDeviceRelease", as: DeviceReference.self),
              let connectionID = symbol("AMDeviceGetConnectionID", as: ConnectionID.self),
              let connect = symbol("AMDeviceConnect", as: DeviceOperation.self),
              let isPaired = symbol("AMDeviceIsPaired", as: DeviceOperation.self),
              let validatePairing = symbol("AMDeviceValidatePairing", as: DeviceOperation.self),
              let startSession = symbol("AMDeviceStartSession", as: DeviceOperation.self),
              let stopSession = symbol("AMDeviceStopSession", as: DeviceOperation.self),
              let disconnect = symbol("AMDeviceDisconnect", as: DeviceOperation.self),
              let copyIdentifier = symbol("AMDeviceCopyDeviceIdentifier", as: CopyIdentifier.self),
              let copyValue = symbol("AMDeviceCopyValue", as: CopyValue.self)
        else {
            dlclose(framework)
            return nil
        }

        self.framework = framework
        self.subscribe = subscribe
        self.retain = retain
        self.release = release
        self.connectionID = connectionID
        self.connect = connect
        self.isPaired = isPaired
        self.validatePairing = validatePairing
        self.startSession = startSession
        self.stopSession = stopSession
        self.disconnect = disconnect
        self.copyIdentifier = copyIdentifier
        self.copyValue = copyValue
    }

    deinit { dlclose(framework) }

    func identifier(for device: UnsafeMutableRawPointer) -> String? {
        guard let value = copyIdentifier(device) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(value).takeRetainedValue() as? String
    }

    func read(device: UnsafeMutableRawPointer, identifier: String) -> Device? {
        guard connect(device) == 0 else { return nil }
        defer { _ = disconnect(device) }
        guard isPaired(device) == 1, validatePairing(device) == 0,
              startSession(device) == 0 else { return nil }
        defer { _ = stopSession(device) }

        guard let deviceClass = value(device, domain: nil, key: "DeviceClass") as? String,
              let kind = Self.kind(for: deviceClass),
              let capacity = value(device, domain: "com.apple.mobile.battery",
                                   key: "BatteryCurrentCapacity") as? NSNumber
        else { return nil }

        let level = capacity.intValue
        guard (0...100).contains(level) else { return nil }
        let name = (value(device, domain: nil, key: "DeviceName") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? kind.displayName
        let charging = (value(device, domain: "com.apple.mobile.battery",
                              key: "BatteryIsCharging") as? NSNumber)?.boolValue ?? false
        let externalPower = (value(device, domain: "com.apple.mobile.battery",
                                   key: "ExternalConnected") as? NSNumber)?.boolValue ?? false

        // Settings store device IDs. Hash the hardware identifier before it
        // enters the UI or UserDefaults while keeping it stable across launches.
        let stableID = SHA256.hash(data: Data(identifier.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return Device(id: "mobile-\(stableID)", name: name, kind: kind,
                      overallPercent: level, isCharging: charging,
                      isConnectedToPower: externalPower, source: .mobileDevice,
                      isConnected: true)
    }

    private func value(_ device: UnsafeMutableRawPointer, domain: String?, key: String) -> AnyObject? {
        let domainObject = domain.map { $0 as NSString }
        let keyObject = key as NSString
        let domainPointer = domainObject.map { Unmanaged.passUnretained($0).toOpaque() }
        let keyPointer = Unmanaged.passUnretained(keyObject).toOpaque()
        guard let result = copyValue(device, domainPointer, keyPointer) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(result).takeRetainedValue()
    }

    private static func kind(for deviceClass: String) -> DeviceKind? {
        switch deviceClass.lowercased() {
        case "iphone": return .iphone
        case "ipad": return .ipad
        default: return nil
        }
    }
}
