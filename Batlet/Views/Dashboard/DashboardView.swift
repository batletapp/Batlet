import SwiftUI
import CoreBluetooth

/// The menu bar panel. Shows grouped device rows, an expandable status card
/// for the selected device, or a friendly state when Bluetooth access is unavailable.
struct DashboardView: View {
    let onOpenSettings: () -> Void
    let onAddDevice: () -> Void
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID: String?
    @State private var isNotConnectedExpanded = false

    private var visibleDevices: [Device] {
        store.devices.filter { !settings.hiddenDeviceIDs.contains($0.id) }
    }

    private var connected: [Device] {
        visibleDevices.filter(\.isConnected)
    }
    private var notConnected: [Device] {
        visibleDevices.filter { !$0.isConnected }
    }
    private var selectedDevice: Device? { visibleDevices.first { $0.id == selectedID } }
    private var listContentHeight: CGFloat {
        let connectedHeight: CGFloat
        if settings.batteryDisplayType == .circle {
            connectedHeight = CGFloat((connected.count + 1) / 2) * 94
        } else {
            connectedHeight = CGFloat(connected.count) * 50
        }
        let disconnectedHeight = isNotConnectedExpanded ? CGFloat(notConnected.count) * 50 : 0
        let sectionCount = (connected.isEmpty ? 0 : 1)
            + (notConnected.isEmpty ? 0 : 1)
        return connectedHeight + disconnectedHeight + CGFloat(sectionCount) * 24
            + (selectedDevice == nil ? 0 : 210) + 28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if store.bluetoothAuthorization == .denied || store.bluetoothAuthorization == .restricted {
                bluetoothOffState
            } else if visibleDevices.isEmpty {
                if store.devices.isEmpty {
                    emptyState
                } else {
                    allHiddenState
                }
            } else {
                ScrollView {
                    content
                }
                .frame(height: min(480, listContentHeight))
                .scrollIndicators(listContentHeight > 480 ? .visible : .hidden)
            }

            Divider()
            footer
        }
        .padding(10)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: colorScheme == .dark ? 0.25 : 0.62)
                    .opacity(0.18))
                .background {
                    PopupGlassSurface()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.38), radius: 22, x: 0, y: 10)
        }
        .onAppear { store.refreshMacBattery() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Batlet").font(.headline.weight(.medium))
                Text("Your batteries, at a glance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Button(action: onAddDevice) {
                    headerActionIcon("plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Device")
                .help("Add Device")
                Button(action: onOpenSettings) {
                    headerActionIcon("gearshape")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Settings")
                .help("Open Settings")
                Button {
                    store.refreshAllSources()
                } label: {
                    headerActionIcon("arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh Devices")
                .help("Refresh Devices")
            }
        }
        .padding(.horizontal, 4)
    }

    private func headerActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if let selectedDevice {
            AirPodsStatusCard(device: selectedDevice) {
                Connector.connect(selectedDevice)
            }
            .environmentObject(settings)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if !connected.isEmpty {
            DeviceGroupCard(title: "Connected", titleColor: .green, count: connected.count) {
                rows(connected)
            }
            .environmentObject(settings)
        }

        if !notConnected.isEmpty {
            DeviceGroupCard(title: nil) {
                Button(action: toggleNotConnected) {
                    HStack {
                        Text("NOT CONNECTED")
                        DeviceCountBadge(count: notConnected.count, color: .red)
                            .accessibilityHidden(true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isNotConnectedExpanded ? 90 : 0))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not Connected, \(notConnected.count) devices")
                .accessibilityValue(isNotConnectedExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Show or hide disconnected devices")
                .help(isNotConnectedExpanded ? "Hide Not Connected Devices" : "Show Not Connected Devices")

                if isNotConnectedExpanded {
                    rows(notConnected, useCircle: false)
                }
            }
            .environmentObject(settings)
        }
    }

    private func toggleNotConnected() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if isNotConnectedExpanded && notConnected.contains(where: { $0.id == selectedID }) {
                selectedID = nil
            }
            isNotConnectedExpanded.toggle()
        }
    }

    @ViewBuilder private func rows(_ devices: [Device], useCircle: Bool = true) -> some View {
        if useCircle && settings.batteryDisplayType == .circle {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(devices) { device in
                    DeviceCircleTile(device: device) { select(device) }
                        .environmentObject(settings)
                }
            }
        } else {
            ForEach(devices) { device in
                DeviceRow(device: device) { select(device) }
                    .environmentObject(settings)
                if device.id != devices.last?.id {
                    Divider()
                        .overlay(Color.gray.opacity(0.35))
                        .padding(.horizontal, -12)
                }
            }
        }
    }

    private func select(_ device: Device) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedID = (selectedID == device.id) ? nil : device.id
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "airpods")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No devices yet").font(.callout)
            Text("Open your AirPods case nearby, or connect a Bluetooth device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var allHiddenState: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("All devices are hidden").font(.callout)
            Button("Manage Devices", action: onOpenSettings)
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var bluetoothOffState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text("Bluetooth access is off").font(.callout.weight(.medium))
            Text("Batlet needs Bluetooth permission to read AirPods battery levels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                PermissionsManager.openBluetoothSettings()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Menu {
                Button {
                    openBluetoothSettings()
                } label: {
                    Label("Open Bluetooth Settings", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(.titleAndIcon)
                }
                Divider()
                Button { } label: {
                    Label("Check for Update", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                }
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                } label: {
                    Label("About", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                }
            } label: {
                Image(systemName: "line.3.horizontal")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
            .help("More actions")
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Quit Batlet")
            .help("Quit Batlet")
        }
        .padding(.horizontal, 4)
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}
