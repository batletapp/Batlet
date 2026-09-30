import Foundation

/// Reads paired Bluetooth devices from `system_profiler SPBluetoothDataType -json`.
/// Uses macOS accessory power data for connected devices when the profiler omits
/// or misreports their battery level.
enum BluetoothInventory {

    /// Runs system_profiler and returns paired devices, including disconnected ones.
    /// Call off the main thread; it spawns a subprocess.
    static func fetch() -> [Device]? {
        guard let json = runSystemProfiler(),
              let sections = json["SPBluetoothDataType"] as? [[String: Any]],
              sections.contains(where: {
                  $0["controller_properties"] != nil
                      || $0["device_connected"] != nil
                      || $0["device_not_connected"] != nil
              })
        else { return nil }
        return parse(json: json,
                     batteryByAddress: BluetoothHIDBatterySource.levelsByAddress(),
                     accessoryBatteryByName: BluetoothAccessoryBatterySource.levelsByName())
    }

    private static func runSystemProfiler() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func parse(json: [String: Any], batteryByAddress: [String: Int] = [:],
                      accessoryBatteryByName: [String: Int] = [:]) -> [Device] {
        guard let rootArray = json["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        var devices: [Device] = []
        for section in rootArray {
            if let connected = section["device_connected"] as? [[String: Any]] {
                devices += connected.compactMap {
                    device(from: $0, connected: true, batteryByAddress: batteryByAddress)
                }
            }
            if let disconnected = section["device_not_connected"] as? [[String: Any]] {
                devices += disconnected.compactMap {
                    device(from: $0, connected: false, batteryByAddress: batteryByAddress)
                }
            }
        }

        let connectedNameCounts = Dictionary(grouping: devices.filter(\.isConnected), by: {
            BluetoothAccessoryBatterySource.normalizedName($0.name)
        }).mapValues(\.count)
        for index in devices.indices where devices[index].isConnected {
            let key = BluetoothAccessoryBatterySource.normalizedName(devices[index].name)
            guard connectedNameCounts[key] == 1,
                  devices[index].left == nil, devices[index].right == nil,
                  devices[index].caseComponent == nil,
                  let percent = accessoryBatteryByName[key]
            else { continue }
            devices[index].overallPercent = percent
            devices[index].batteryReadingSource = .accessoryPower
        }
        return devices
    }

    /// Each entry is a single-key dict: { "<Device Name>": { ...properties... } }.
    private static func device(
        from entry: [String: Any], connected: Bool, batteryByAddress: [String: Int]
    ) -> Device? {
        guard let name = entry.keys.first,
              let props = entry[name] as? [String: Any] else { return nil }

        let address = (props["device_address"] as? String) ?? name
        let normalizedAddress = address.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let main = batteryPercent(props["device_batteryLevelMain"])
            ?? (connected ? batteryByAddress[normalizedAddress] : nil)
        let left = batteryPercent(props["device_batteryLevelLeft"])
        let right = batteryPercent(props["device_batteryLevelRight"])
        let caseLevel = batteryPercent(props["device_batteryLevelCase"])

        let minorType = (props["device_minorType"] as? String) ?? ""
        let kind = classify(name: name, minorType: minorType)

        let overall: Int?
        if let l = left, let r = right {
            overall = min(l, r)
        } else {
            overall = main ?? left ?? right ?? caseLevel
        }

        return Device(
            id: "bt-\(address)",
            name: name,
            kind: kind,
            overallPercent: overall,
            isCharging: false,
            left: left.map { BatteryComponent(percent: $0) },
            right: right.map { BatteryComponent(percent: $0) },
            caseComponent: caseLevel.map { BatteryComponent(percent: $0) },
            lastSeen: Date(),
            source: .systemProfiler,
            isConnected: connected
        )
    }

    /// Parses values like "80%" or 80 into an Int percentage.
    private static func batteryPercent(_ value: Any?) -> Int? {
        if let s = value as? String {
            let digits = s.filter(\.isNumber)
            return Int(digits)
        }
        if let n = value as? Int { return n }
        return nil
    }

    static func classify(name: String, minorType: String) -> DeviceKind {
        let n = name.lowercased()
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods max") { return .airpodsMax }
        if n.contains("airpods") { return .airpods }
        if n.contains("beats") { return .beats }
        if n.contains("magic mouse") { return .magicMouse }
        if n.contains("magic keyboard") { return .magicKeyboard }
        if n.contains("magic trackpad") { return .magicTrackpad }
        if n.contains("keyboard") || n.contains("mx keys") { return .keyboard }
        if n.contains("mouse") || n.contains("mx master") { return .mouse }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("headphones") || n.contains("headset") || n.contains("earbuds") {
            return .headphones
        }

        if n.contains("iphone") { return .iphone }
        if n.contains("ipad") { return .ipad }
        if n.contains("imac") || n.contains("macbook") { return .mac }

        switch minorType.lowercased() {
        case let t where t.contains("mouse"): return .mouse
        case let t where t.contains("keyboard"): return .keyboard
        case let t where t.contains("trackpad"): return .trackpad
        case let t where t.contains("computer"): return .mac
        case let t where t.contains("headphone"), let t where t.contains("headset"):
            return .headphones
        default:
            return .unknown
        }
    }
}
