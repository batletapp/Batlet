import Foundation
import IOKit.ps

/// Reads this Mac's internal battery via IOKit power sources. Returns nil on desktops
/// (no internal battery), so only portable Macs show a battery.
enum SystemBatterySource {
    static func macDevice() -> Device? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            if let device = device(from: desc, name: Host.current().localizedName ?? "This Mac") {
                return device
            }
        }
        return nil
    }

    static func device(from desc: [String: Any], name: String) -> Device? {
        guard let type = desc[kIOPSTypeKey as String] as? String,
              type == (kIOPSInternalBatteryType as String)
        else { return nil }

        let current = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
        let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
        let connectedToPower = (desc[kIOPSPowerSourceStateKey as String] as? String)
            == (kIOPSACPowerValue as String)
        let percent = maxCap > 0 ? Int((Double(current) / Double(maxCap)) * 100.0) : current

        return Device(
            id: "mac-internal",
            name: name,
            kind: .macBook,
            overallPercent: percent,
            isCharging: charging,
            isConnectedToPower: connectedToPower,
            lastSeen: Date(),
            source: .systemPower,
            isConnected: true
        )
    }
}
