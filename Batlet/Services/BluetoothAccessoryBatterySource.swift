import Foundation
import IOKit.ps
import Darwin

/// Reads the accessory battery snapshot used by macOS for Bluetooth peripherals.
enum BluetoothAccessoryBatterySource {
    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    private static let accessorySourceType: Int32 = 4

    static func levelsByName() -> [String: Int] {
        // This IOKit entry point is used by pmset but is absent from the public SDK.
        // Resolve it at runtime so older or changed systems can fall back to GATT/HID.
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        else { return [:] }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return [:] }
        let copySources = unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
        guard let snapshot = copySources(accessorySourceType)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return [:] }

        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return levels(from: descriptions)
    }

    static func levels(from descriptions: [[String: Any]]) -> [String: Int] {
        var levels: [String: Int] = [:]
        var ambiguousNames: Set<String> = []
        for desc in descriptions {
            guard (desc[kIOPSTypeKey as String] as? String) == "Accessory Source",
                  (desc["Transport Type"] as? String) == "Bluetooth",
                  let name = desc[kIOPSNameKey as String] as? String,
                  let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = desc[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0, (0...maximum).contains(current)
            else { continue }

            let key = normalizedName(name)
            guard !key.isEmpty else { continue }
            if levels[key] != nil { ambiguousNames.insert(key) }
            levels[key] = Int((Double(current) / Double(maximum) * 100).rounded())
        }
        for name in ambiguousNames { levels.removeValue(forKey: name) }
        return levels
    }

    static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
