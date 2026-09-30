import Foundation
import IOKit

/// Reads the battery level exposed by connected Bluetooth HID devices, such as
/// a Magic Mouse, when system_profiler omits it.
enum BluetoothHIDBatterySource {
    /// Keys are lowercase Bluetooth addresses without separators.
    static func levelsByAddress() -> [String: Int] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var levels: [String: Int] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let address = IORegistryEntryCreateCFProperty(
                service, "BD_ADDR" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Data,
                  address.count == 6,
                  let battery = IORegistryEntryCreateCFProperty(
                    service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? NSNumber,
                  (0...100).contains(battery.intValue)
            else { continue }

            let key = address.map { String(format: "%02x", $0) }.joined()
            levels[key] = battery.intValue
        }
        return levels
    }
}
