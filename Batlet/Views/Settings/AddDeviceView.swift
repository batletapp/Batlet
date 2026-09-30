import SwiftUI

/// A deliberate, short Bluetooth discovery session for audio and input devices.
struct AddDeviceView: View {
    static let windowSize = CGSize(width: 520, height: 500)

    @EnvironmentObject private var store: DeviceStore
    @ObservedObject private var discovery = NearbyDeviceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add Device")
                        .font(.title2.weight(.semibold))
                    Text("Put your device in pairing mode, then scan nearby.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(discovery.isScanning ? "Stop" : "Scan Nearby") {
                    if discovery.isScanning {
                        discovery.stopScan()
                    } else {
                        discovery.scanNow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled((!store.bluetoothPoweredOn && !discovery.isScanning)
                          || (!discovery.isScanning && discovery.hasPendingConnection))
            }

            if discovery.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for audio devices, mice, trackpads, and keyboards…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !store.bluetoothPoweredOn {
                ContentUnavailableView(
                    "Bluetooth Is Off", systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Turn on Bluetooth to find nearby devices.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if discovery.discoveredDevices.isEmpty {
                ContentUnavailableView(
                    discovery.isScanning ? "Scanning Nearby" : "No Devices Found",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(discovery.scanMessage ??
                        (discovery.isScanning
                         ? "Devices will appear here as they are found."
                         : "Press Scan Nearby to look for devices you can connect."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(discovery.discoveredDevices) { candidate in
                    deviceRow(candidate)
                }
                .listStyle(.inset)
            }

            Text("Devices without a direct pairing address open Bluetooth Settings. TVs and other video devices are excluded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(SettingsAppearance.background)
        .onDisappear { discovery.stopScan() }
    }

    private func deviceRow(_ candidate: NearbyDeviceCandidate) -> some View {
        let phase = discovery.connectionState(for: candidate)
        return HStack(spacing: 12) {
            DeviceIconView(kind: candidate.kind, size: 28)
                .frame(width: 34)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(.body.weight(.medium))
                Text(phase == .failed ? "Couldn’t connect. Try again or use Bluetooth Settings."
                     : candidate.isPaired ? "Paired · \(candidate.kind.displayName)"
                     : candidate.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(phase == .failed ? .red : .secondary)
            }
            Spacer()
            switch phase {
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Connecting…").font(.caption).foregroundStyle(.secondary)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Button("Retry") {
                    discovery.connect(candidate)
                }
                .buttonStyle(.bordered)
                .disabled(discovery.hasPendingConnection)
                Button("Settings") {
                    discovery.openBluetoothSettings()
                }
                .buttonStyle(.link)
            case nil:
                Button(candidate.actionTitle) {
                    discovery.connect(candidate)
                }
                .buttonStyle(.bordered)
                .disabled(discovery.hasPendingConnection)
            }
        }
        .padding(.vertical, 5)
    }
}
