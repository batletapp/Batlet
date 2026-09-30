import SwiftUI

struct DevicesSettingsView: View {
    let onAddDevice: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: DeviceStore
    @State private var configuringAlert: Device?

    private var connectedDevices: [Device] {
        store.devices.filter { $0.isConnected && !settings.hiddenDeviceIDs.contains($0.id) }
    }

    private var disconnectedDevices: [Device] {
        store.devices.filter { !$0.isConnected && !settings.hiddenDeviceIDs.contains($0.id) }
    }

    private var hiddenDevices: [Device] {
        store.devices.filter { settings.hiddenDeviceIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Devices").font(.headline)
                Spacer()
                Button("Add Device", systemImage: "plus", action: onAddDevice)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if store.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "ipodtouch.slash",
                    description: Text("Devices appear here as Batlet discovers them.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !connectedDevices.isEmpty {
                            deviceSection(
                                "Connected",
                                symbol: "checkmark.circle.fill",
                                color: .green,
                                devices: connectedDevices
                            )
                        }
                        if !disconnectedDevices.isEmpty {
                            deviceSection(
                                "Not Connected",
                                symbol: "circle.dashed",
                                color: .secondary,
                                devices: disconnectedDevices
                            )
                        }
                        if !hiddenDevices.isEmpty {
                            deviceSection(
                                "Hidden from Panel",
                                symbol: "eye.slash",
                                color: .orange,
                                devices: hiddenDevices
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            if !store.devices.contains(where: { $0.source == .mobileDevice }) {
                Divider()
                Text("To show an iPhone or iPad, connect it with a data-capable USB cable and allow Trust if prompted. Make sure it appears in Finder, then enable “Show this device when on Wi-Fi” for wireless updates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(SettingsAppearance.background)
        .sheet(item: $configuringAlert) { device in
            BatteryAlertSheet(device: device, existing: settings.alert(for: device.id))
                .environmentObject(settings)
        }
    }

    private func deviceSection(
        _ title: String,
        symbol: String,
        color: Color,
        devices: [Device]
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(devices.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(color.opacity(0.07))

            Divider()

            ForEach(devices) { device in
                row(for: device)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                if device.id != devices.last?.id {
                    Divider()
                        .padding(.leading, 46)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(devices.count) devices")
    }

    private func row(for device: Device) -> some View {
        let hidden = settings.hiddenDeviceIDs.contains(device.id)
        let alert = settings.alert(for: device.id)

        return HStack(spacing: 10) {
            DeviceIconView(kind: device.kind, size: 20)
                .frame(width: 22)
                .foregroundStyle(hidden ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.displayName(for: device))
                    .foregroundStyle(hidden ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if hidden {
                        Text(device.isConnected ? "Connected" : "Not connected")
                        Text("·")
                    }
                    Label(alertStatus(for: alert), systemImage: alertIcon(for: alert))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let percent = device.overallPercent {
                Text("\(percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                BatteryGlyphView(percent: percent, isCharging: device.isCharging)
            }

            Menu {
                Button("Battery Alerts…", systemImage: "bell") {
                    configuringAlert = device
                }
                Divider()
                Button(hidden ? "Show in Panel" : "Hide from Panel",
                       systemImage: hidden ? "eye" : "eye.slash") {
                    settings.toggleHidden(device.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(settings.displayName(for: device))")
        }
        .padding(.vertical, 2)
    }

    private func alertStatus(for alert: BatteryAlert?) -> String {
        guard let alert else { return "No alert set" }
        if alert.lowEnabled && alert.chargedEnabled { return "Low & charged alerts on" }
        if alert.lowEnabled { return "Low alert at \(alert.lowThreshold)%" }
        if alert.chargedEnabled { return "Charged alert on" }
        return "Alerts off"
    }

    private func alertIcon(for alert: BatteryAlert?) -> String {
        guard let alert, alert.lowEnabled || alert.chargedEnabled else { return "bell.slash" }
        return "bell.fill"
    }

}
