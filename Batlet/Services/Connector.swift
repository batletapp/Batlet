import Foundation
import IOBluetooth

/// Best-effort connect for already-paired classic-Bluetooth devices (e.g. AirPods).
/// Matches a paired IOBluetoothDevice by name and opens a baseband connection.
///
/// This is inherently best-effort: it only works for devices already paired to this Mac,
/// and connection behavior varies by device and macOS version.
enum Connector {
    /// Issues a baseband request. The system connection event confirms the outcome later.
    static func requestPairedConnection(address: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let target = IOBluetoothDevice(addressString: address),
                  target.isPaired(), !target.isConnected() else { return }
            _ = target.openConnection()
        }
    }

    @discardableResult
    static func connect(_ device: Device) -> Bool {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return false
        }
        let target = paired.first {
            ($0.name ?? "").caseInsensitiveCompare(device.name) == .orderedSame
        }
        guard let target else { return false }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = target.openConnection()
        }
        return true
    }
}
