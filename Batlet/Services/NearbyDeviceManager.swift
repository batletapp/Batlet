import Foundation
import Combine
import IOBluetooth
import AppKit

/// Limits prompts for a device that advertises repeatedly or stays discoverable.
struct NearbyPromptGate {
    private var sightings: [String: (date: Date, count: Int)] = [:]
    private var lastPrompted: [String: Date] = [:]
    let cooldown: TimeInterval = 60 * 60

    mutating func shouldPrompt(address: String, at now: Date, needsSecondSighting: Bool) -> Bool {
        if let previous = lastPrompted[address], now.timeIntervalSince(previous) < cooldown {
            return false
        }
        if needsSecondSighting {
            let previous = sightings[address]
            let count = previous.map { now.timeIntervalSince($0.date) <= 15 ? $0.count + 1 : 1 } ?? 1
            sightings[address] = (now, count)
            guard count >= 2 else { return false }
        }
        sightings[address] = nil
        lastPrompted[address] = now
        return true
    }
}

enum NearbyPromptPolicy {
    static func kind(name: String, knownKind: DeviceKind?,
                     classicMajorClass: BluetoothDeviceClassMajor,
                     classicMinorClass: BluetoothDeviceClassMinor = 0) -> DeviceKind {
        if isTelevisionOrVideoDevice(name: name, majorClass: classicMajorClass,
                                    minorClass: classicMinorClass) {
            return .unknown
        }
        if let knownKind, knownKind != .unknown { return knownKind }
        let named = BluetoothInventory.classify(name: name, minorType: "")
        if named != .unknown { return named }
        if classicMajorClass == kBluetoothDeviceClassMajorAudio { return .headphones }
        if classicMajorClass == kBluetoothDeviceClassMajorPeripheral {
            switch classicMinorClass & 0x30 {
            case 0x10, 0x30: return .keyboard
            case 0x20: return .mouse
            default: break
            }
        }
        return .unknown
    }

    private static func isTelevisionOrVideoDevice(
        name: String, majorClass: BluetoothDeviceClassMajor,
        minorClass: BluetoothDeviceClassMinor
    ) -> Bool {
        let tokens = Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if !tokens.isDisjoint(with: ["tv", "television", "webos", "tizen", "bravia", "chromecast", "smarttv"]) {
            return true
        }
        guard majorClass == kBluetoothDeviceClassMajorAudio else { return false }
        switch minorClass {
        case BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioSetTopBox),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVCR),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVideoCamera),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioCamcorder),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVideoMonitor),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVideoDisplayAndLoudspeaker),
             BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioVideoConferencing):
            return true
        default:
            return false
        }
    }

    static func supports(_ kind: DeviceKind, isPaired: Bool) -> Bool {
        switch kind {
        case .airpods, .airpodsPro, .airpodsMax, .airpods3, .airpodsPro2, .airpods4,
             .beats, .headphones, .magicMouse, .mouse, .magicTrackpad, .trackpad,
             .magicKeyboard, .keyboard:
            return true
        default:
            return false
        }
    }
}

struct ClassicNearbySighting {
    let address: String
    let name: String?
    let majorClass: BluetoothDeviceClassMajor
    let minorClass: BluetoothDeviceClassMinor
    let isPaired: Bool
    let isConnected: Bool

    init?(device: IOBluetoothDevice?) {
        guard let device, let address = device.addressString else { return nil }
        self.address = address
        name = device.name
        majorClass = device.deviceClassMajor
        minorClass = device.deviceClassMinor
        isPaired = device.isPaired()
        isConnected = device.isConnected()
    }
}

struct NearbyDeviceCandidate: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: DeviceKind
    let address: String?
    let isPaired: Bool
    let batteryPercent: Int?

    var actionTitle: String { address == nil ? "Open Settings" : "Connect" }
}

enum NearbyConnectionPhase: Equatable {
    case connecting
    case connected
    case failed
}

/// Only a system connection event or a timeout ends a connection attempt.
struct NearbyConnectionTracker {
    private(set) var states: [String: NearbyConnectionPhase] = [:]

    func state(for id: String) -> NearbyConnectionPhase? { states[id] }

    mutating func begin(_ id: String) -> Bool {
        guard states[id] != .connecting else { return false }
        states[id] = .connecting
        return true
    }

    mutating func systemConnected(_ id: String) -> Bool {
        guard states[id] != nil, states[id] != .connected else { return false }
        states[id] = .connected
        return true
    }

    mutating func timeout(_ id: String) -> Bool {
        guard states[id] == .connecting else { return false }
        states[id] = .failed
        return true
    }
}

/// Collects discoverable devices during a user-requested scan. Optional background
/// suggestions reuse the existing BLE battery scan without running classic inquiries.
@MainActor
final class NearbyDeviceManager: NSObject, ObservableObject {
    static let shared = NearbyDeviceManager()

    @Published private(set) var discoveredDevices: [NearbyDeviceCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanMessage: String?
    @Published private(set) var connectionStates: [String: NearbyConnectionPhase] = [:]

    private var store: DeviceStore?
    private var settings: AppSettings?
    private var subscriptions: Set<AnyCancellable> = []
    private var inquiry: IOBluetoothDeviceInquiry?
    private var scanTimeout: DispatchWorkItem?
    private var pairedCache: [IOBluetoothDevice] = []
    private var pairedCacheDate = Date.distantPast
    private var gate = NearbyPromptGate()
    private var activePairing: IOBluetoothDevicePair?
    private var pairingName: String?
    private var pairingAttemptID: String?
    private var connectionTracker = NearbyConnectionTracker()
    private struct ConnectionAttempt {
        let token: UUID
        let candidate: NearbyDeviceCandidate
        let fromBackgroundPrompt: Bool
        let timeout: DispatchWorkItem
    }
    private var connectionAttempts: [String: ConnectionAttempt] = [:]
    private var attemptedCandidates: [String: NearbyDeviceCandidate] = [:]

    var hasPendingConnection: Bool { !connectionAttempts.isEmpty }

    func connectionState(for candidate: NearbyDeviceCandidate) -> NearbyConnectionPhase? {
        connectionStates[candidate.id]
    }

    func start(store: DeviceStore, settings: AppSettings) {
        guard self.store == nil else { return }
        self.store = store
        self.settings = settings

        store.nearbyAdvertisements
            .sink { [weak self] advertisement in self?.considerBLE(advertisement) }
            .store(in: &subscriptions)
        store.connectionEvents
            .sink { [weak self] device in
                guard device.isConnected else { return }
                self?.handleSystemConnection(device)
            }
            .store(in: &subscriptions)
        store.$devices
            .sink { [weak self] devices in
                for device in devices where device.isConnected {
                    self?.handleSystemConnection(device)
                }
            }
            .store(in: &subscriptions)
        settings.$nearbyPromptsEnabled
            .dropFirst()
            .sink { enabled in
                if !enabled { AlertPresenter.shared.removeAllNearbyPrompts() }
            }
            .store(in: &subscriptions)
    }

    func scanNow() {
        guard !isScanning, !hasPendingConnection else { return }
        guard store?.bluetoothPoweredOn == true else {
            scanMessage = "Turn on Bluetooth to scan for devices."
            return
        }
        connectionTracker = NearbyConnectionTracker()
        connectionStates = [:]
        attemptedCandidates.removeAll()
        discoveredDevices = []
        scanMessage = nil
        isScanning = true
        startClassicInquiry()
        guard isScanning else { return }
        let timeout = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        scanTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    }

    func stopScan() {
        guard isScanning else { return }
        scanTimeout?.cancel()
        scanTimeout = nil
        inquiry?.stop()
        inquiry = nil
        isScanning = false
        scanMessage = discoveredDevices.isEmpty ? "No supported devices found. Try pairing mode and scan again." : nil
    }

    func connect(_ candidate: NearbyDeviceCandidate) {
        guard let address = candidate.address else {
            openBluetoothSettings()
            return
        }
        connect(address: address, candidate: candidate, fromBackgroundPrompt: false)
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    private func considerBLE(_ advertisement: NearbyAdvertisement) {
        guard advertisement.rssi >= -85 else { return }
        if let paired = uniquelyPaired(named: advertisement.name),
           let candidate = addressCandidate(
            address: paired.addressString, name: paired.name,
            isPaired: paired.isPaired(), isConnected: paired.isConnected(),
            majorClass: paired.deviceClassMajor, minorClass: paired.deviceClassMinor,
            batteryPercent: advertisement.batteryPercent
           ) {
            if isScanning { addCandidate(candidate) }
            if settings?.nearbyPromptsEnabled == true {
                showBackgroundPrompt(for: candidate, needsSecondSighting: true)
            }
        } else if isScanning {
            let kind = NearbyPromptPolicy.kind(name: advertisement.name, knownKind: nil,
                                               classicMajorClass: 0)
            if NearbyPromptPolicy.supports(kind, isPaired: false) {
                addCandidate(NearbyDeviceCandidate(
                    id: "ble-\(Self.nameKey(advertisement.name))",
                    name: advertisement.name, kind: kind, address: nil,
                    isPaired: false, batteryPercent: advertisement.batteryPercent
                ))
            }
        }
    }

    private func startClassicInquiry() {
        guard isScanning, store?.bluetoothPoweredOn == true, inquiry == nil else { return }
        let inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.inquiryLength = 8
        inquiry?.updateNewDeviceNames = true
        inquiry?.searchType = 3 // Classic (1) and Low Energy (2)
        self.inquiry = inquiry
        guard inquiry?.start() == kIOReturnSuccess else {
            self.inquiry = nil
            stopScan()
            scanMessage = "Bluetooth scan could not start. Try again in a moment."
            return
        }
    }

    private func considerClassic(_ sighting: ClassicNearbySighting) {
        guard isScanning,
              let candidate = addressCandidate(
                address: sighting.address, name: sighting.name,
                isPaired: sighting.isPaired, isConnected: sighting.isConnected,
                majorClass: sighting.majorClass, minorClass: sighting.minorClass,
                batteryPercent: nil
              ) else { return }
        addCandidate(candidate)
    }

    private func addressCandidate(
        address: String?, name: String?, isPaired: Bool, isConnected: Bool,
        majorClass: BluetoothDeviceClassMajor, minorClass: BluetoothDeviceClassMinor,
        batteryPercent: Int?
    ) -> NearbyDeviceCandidate? {
        guard let store, store.bluetoothPoweredOn, !isConnected,
              let address, let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let key = Self.addressKey(address)
        let exact = store.devices.first {
            $0.id.hasPrefix("bt-") && Self.addressKey(String($0.id.dropFirst(3))) == key
        }
        let nameMatches = store.devices.filter { Self.nameKey($0.name) == Self.nameKey(name) }
        guard exact != nil || nameMatches.count <= 1 else { return nil }
        let known = exact ?? nameMatches.first
        guard known?.isConnected != true else { return nil }
        let kind = NearbyPromptPolicy.kind(name: name, knownKind: known?.kind,
                                           classicMajorClass: majorClass,
                                           classicMinorClass: minorClass)
        guard NearbyPromptPolicy.supports(kind, isPaired: isPaired) else { return nil }
        return NearbyDeviceCandidate(id: "bt-\(key)", name: name, kind: kind,
                                     address: address, isPaired: isPaired,
                                     batteryPercent: batteryPercent)
    }

    private func addCandidate(_ candidate: NearbyDeviceCandidate) {
        if candidate.address != nil {
            discoveredDevices.removeAll {
                $0.address == nil && Self.nameKey($0.name) == Self.nameKey(candidate.name)
            }
        }
        if let index = discoveredDevices.firstIndex(where: { $0.id == candidate.id }) {
            discoveredDevices[index] = candidate
        } else {
            discoveredDevices.append(candidate)
        }
        discoveredDevices.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func showBackgroundPrompt(for candidate: NearbyDeviceCandidate,
                                      needsSecondSighting: Bool) {
        guard !isScanning, let settings, let address = candidate.address,
              !settings.hiddenDeviceIDs.contains(candidate.id),
              !settings.hiddenDeviceIDs.contains(Self.nameKey(candidate.name)) else { return }
        let key = Self.addressKey(address)
        guard gate.shouldPrompt(address: key, at: Date(),
                                needsSecondSighting: needsSecondSighting) else { return }
        AlertPresenter.shared.show(AlertPresentation(
            title: candidate.name,
            subtitle: "Nearby and ready to connect",
            symbol: candidate.kind.symbolName,
            percent: candidate.batteryPercent,
            tone: .neutral,
            autoDismiss: 15,
            deviceImageName: ConnectionPopupImage.assetName(for: candidate.kind),
            isConnectionEvent: true,
            nearbyDeviceAddress: key,
            primaryAction: { [weak self] in
                guard let self, let address = candidate.address else { return }
                self.connect(address: address, candidate: candidate,
                             fromBackgroundPrompt: true)
            },
            expiresAt: Date().addingTimeInterval(30)
        ))
    }

    private func connect(address: String, candidate: NearbyDeviceCandidate,
                         fromBackgroundPrompt: Bool) {
        let id = candidate.id
        guard connectionTracker.begin(id) else { return }
        connectionStates = connectionTracker.states
        attemptedCandidates[id] = candidate

        let alreadyPaired = IOBluetoothDevice(addressString: address)?.isPaired() == true
        let token = UUID()
        let timeout = DispatchWorkItem { [weak self] in
            self?.connectionTimedOut(id: id, token: token)
        }
        connectionAttempts[id] = ConnectionAttempt(
            token: token, candidate: candidate,
            fromBackgroundPrompt: fromBackgroundPrompt, timeout: timeout
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + (alreadyPaired ? 20 : 60), execute: timeout)

        if fromBackgroundPrompt {
            AlertPresenter.shared.show(AlertPresentation(
                title: candidate.name, subtitle: "Connecting…",
                symbol: candidate.kind.symbolName, percent: nil, tone: .neutral,
                autoDismiss: alreadyPaired ? 20 : 60,
                deviceImageName: ConnectionPopupImage.assetName(for: candidate.kind),
                isConnectionEvent: true,
                nearbyDeviceAddress: Self.addressKey(address)
            ))
        }

        if let connected = store?.devices.first(where: {
            $0.isConnected && Self.matches($0, candidate: candidate)
        }) {
            handleSystemConnection(connected)
            return
        }

        guard alreadyPaired else {
            startPairing(address: address, name: candidate.name, attemptID: id)
            return
        }
        Connector.requestPairedConnection(address: address)
    }

    private func startPairing(address: String, name: String, attemptID: String) {
        guard activePairing == nil,
              let device = IOBluetoothDevice(addressString: address),
              let pairing = IOBluetoothDevicePair(device: device)
        else {
            resetConnectionTimeout(for: attemptID, after: 6)
            return
        }
        pairing.delegate = self
        activePairing = pairing
        pairingName = name
        pairingAttemptID = attemptID
        guard pairing.start() == kIOReturnSuccess else {
            activePairing = nil
            pairingName = nil
            pairingAttemptID = nil
            resetConnectionTimeout(for: attemptID, after: 6)
            return
        }
    }

    private func finishPairing(error: IOReturn) {
        guard let pairing = activePairing else { return }
        let address = pairing.device()?.addressString
        let attemptID = pairingAttemptID
        activePairing = nil
        pairingName = nil
        pairingAttemptID = nil
        if let attemptID {
            resetConnectionTimeout(for: attemptID,
                                   after: error == kIOReturnSuccess ? 20 : 6)
        }
        guard error == kIOReturnSuccess, let address else { return }
        Connector.requestPairedConnection(address: address)
    }

    private func resetConnectionTimeout(for id: String, after delay: TimeInterval) {
        guard let previous = connectionAttempts[id] else { return }
        previous.timeout.cancel()
        let token = UUID()
        let timeout = DispatchWorkItem { [weak self] in
            self?.connectionTimedOut(id: id, token: token)
        }
        connectionAttempts[id] = ConnectionAttempt(
            token: token, candidate: previous.candidate,
            fromBackgroundPrompt: previous.fromBackgroundPrompt, timeout: timeout
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }

    private func connectionTimedOut(id: String, token: UUID) {
        guard let attempt = connectionAttempts[id], attempt.token == token else { return }
        if let connected = store?.devices.first(where: {
            $0.isConnected && Self.matches($0, candidate: attempt.candidate)
        }) {
            handleSystemConnection(connected)
            return
        }
        connectionAttempts[id] = nil
        if pairingAttemptID == id {
            activePairing?.stop()
            activePairing = nil
            pairingName = nil
            pairingAttemptID = nil
        }
        guard connectionTracker.timeout(id) else { return }
        connectionStates = connectionTracker.states
        if attempt.fromBackgroundPrompt, let address = attempt.candidate.address {
            AlertPresenter.shared.removeNearbyPrompt(for: Self.addressKey(address))
            showConnectionFailure(for: attempt.candidate.name, address: address)
        }
    }

    private func handleSystemConnection(_ device: Device) {
        removePrompt(for: device)
        var changed = false
        for (id, candidate) in attemptedCandidates
            where Self.matches(device, candidate: candidate) {
            if let attempt = connectionAttempts.removeValue(forKey: id) {
                attempt.timeout.cancel()
            }
            if let address = candidate.address {
                AlertPresenter.shared.removeNearbyPrompt(for: Self.addressKey(address))
            }
            changed = connectionTracker.systemConnected(id) || changed
        }
        if changed { connectionStates = connectionTracker.states }
    }

    private static func matches(_ device: Device, candidate: NearbyDeviceCandidate) -> Bool {
        if device.id.hasPrefix("bt-"), let address = candidate.address {
            return addressKey(String(device.id.dropFirst(3))) == addressKey(address)
        }
        return nameKey(device.name) == nameKey(candidate.name)
    }

    private func showConnectionFailure(for name: String, address: String) {
        AlertPresenter.shared.show(AlertPresentation(
            title: name, subtitle: "Couldn’t connect. Check Bluetooth Settings.",
            symbol: "exclamationmark.triangle", percent: nil, tone: .warning,
            nearbyDeviceAddress: Self.addressKey(address)
        ))
    }

    private func removePrompt(for device: Device) {
        if device.id.hasPrefix("bt-") {
            AlertPresenter.shared.removeNearbyPrompt(
                for: Self.addressKey(String(device.id.dropFirst(3)))
            )
            return
        }
        guard let paired = uniquelyPaired(named: device.name),
              let address = paired.addressString else { return }
        AlertPresenter.shared.removeNearbyPrompt(for: Self.addressKey(address))
    }

    private func uniquelyPaired(named name: String) -> IOBluetoothDevice? {
        let matches = pairedDevices().filter { Self.nameKey($0.name) == Self.nameKey(name) }
        return matches.count == 1 ? matches[0] : nil
    }

    private func pairedDevices() -> [IOBluetoothDevice] {
        if Date().timeIntervalSince(pairedCacheDate) > 30 {
            pairedCache = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            pairedCacheDate = Date()
        }
        return pairedCache
    }

    private static func nameKey(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func addressKey(_ address: String?) -> String {
        (address ?? "").lowercased().filter(\.isHexDigit)
    }
}

extension NearbyDeviceManager: IOBluetoothDeviceInquiryDelegate {
    @objc nonisolated func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!
    ) {
        guard let sighting = ClassicNearbySighting(device: device) else { return }
        Task { @MainActor [weak self] in self?.considerClassic(sighting) }
    }

    @objc nonisolated func deviceInquiryDeviceNameUpdated(
        _ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!,
        devicesRemaining: UInt32
    ) {
        guard let sighting = ClassicNearbySighting(device: device) else { return }
        Task { @MainActor [weak self] in self?.considerClassic(sighting) }
    }

    @objc nonisolated func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool
    ) {
        guard let sender else { return }
        let inquiryID = ObjectIdentifier(sender)
        let sightings = (sender.foundDevices() as? [IOBluetoothDevice] ?? [])
            .compactMap { ClassicNearbySighting(device: $0) }
        Task { @MainActor [weak self] in
            guard let self, let current = self.inquiry,
                  ObjectIdentifier(current) == inquiryID else { return }
            for sighting in sightings { self.considerClassic(sighting) }
            self.inquiry = nil
            self.stopScan()
        }
    }
}

extension NearbyDeviceManager: IOBluetoothDevicePairDelegate {
    @objc nonisolated func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        Task { @MainActor [weak self] in self?.finishPairing(error: error) }
    }

    @objc nonisolated func devicePairingUserConfirmationRequest(
        _ sender: Any!, numericValue: BluetoothNumericValue
    ) {
        Task { @MainActor [weak self] in
            guard let self, let pairing = self.activePairing else { return }
            let alert = NSAlert()
            alert.messageText = "Confirm Bluetooth pairing"
            alert.informativeText = "Does \(numericValue) match the code on \(self.pairingName ?? "the device")?"
            alert.addButton(withTitle: "Pair")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            pairing.replyUserConfirmation(alert.runModal() == .alertFirstButtonReturn)
        }
    }

    @objc nonisolated func devicePairingPINCodeRequest(_ sender: Any!) {
        Task { @MainActor [weak self] in
            guard let self, let pairing = self.activePairing else { return }
            let alert = NSAlert()
            alert.messageText = "Enter Bluetooth PIN"
            alert.informativeText = "Enter the PIN for \(self.pairingName ?? "the device")."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.placeholderString = "PIN"
            alert.accessoryView = field
            alert.addButton(withTitle: "Pair")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else {
                pairing.stop()
                self.activePairing = nil
                self.pairingName = nil
                if let attemptID = self.pairingAttemptID {
                    self.resetConnectionTimeout(for: attemptID, after: 6)
                }
                self.pairingAttemptID = nil
                return
            }
            let bytes = Array(field.stringValue.utf8.prefix(16))
            var pin = BluetoothPINCode()
            withUnsafeMutableBytes(of: &pin) { buffer in
                buffer.copyBytes(from: bytes)
            }
            pairing.replyPINCode(bytes.count, pinCode: &pin)
        }
    }

    @objc nonisolated func devicePairingUserPasskeyNotification(
        _ sender: Any!, passkey: BluetoothPasskey
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.activePairing != nil else { return }
            let alert = NSAlert()
            alert.messageText = "Enter Bluetooth passkey"
            alert.informativeText = "Type \(String(format: "%06d", passkey)) on \(self.pairingName ?? "the device"), then press Return there."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
