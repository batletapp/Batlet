import SwiftUI

/// Expanded detail for a selected device: large icon, per-component battery (left/right/case),
/// and a connect action for AirPods-family devices.
struct AirPodsStatusCard: View {
    @EnvironmentObject private var settings: AppSettings
    let device: Device
    var onConnect: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if settings.batteryDisplayType == .bar || hasComponents || device.overallPercent == nil {
                DeviceIconView(kind: device.kind, size: 40)
            }

            Text(settings.displayName(for: device))
                .font(.headline)

            if hasComponents {
                HStack(spacing: settings.batteryDisplayType == .circle ? 12 : 18) {
                    if let left = device.left { component("Left", left) }
                    if let right = device.right { component("Right", right) }
                    if let caseComp = device.caseComponent { component("Case", caseComp) }
                }
            } else if let percent = device.overallPercent {
                if settings.batteryDisplayType == .circle {
                    VStack(spacing: 5) {
                        BatteryRingView(percent: percent, symbolName: device.kind.symbolName,
                                        deviceKind: device.kind,
                                        isCharging: device.isCharging,
                                        isConnectedToPower: device.isConnectedToPower,
                                        diameter: 76)
                        Text("\(percent)%").font(.title3.monospacedDigit())
                    }
                } else {
                    HStack(spacing: 6) {
                        BatteryGlyphView(percent: percent, isCharging: device.isCharging,
                                         isConnectedToPower: device.isConnectedToPower, height: 16)
                        Text("\(percent)%").font(.title3.monospacedDigit())
                    }
                }
            } else if device.source != .systemPower {
                Text(device.isConnected ? "Connected · Battery unavailable" : "Not connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if device.kind.isAirPodsFamily {
                Button(device.isConnected ? "Connected" : "Connect") { onConnect?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(device.isConnected)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var hasComponents: Bool {
        device.left != nil || device.right != nil || device.caseComponent != nil
    }

    private func component(_ label: String, _ battery: BatteryComponent) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if settings.batteryDisplayType == .circle {
                BatteryRingView(percent: battery.percent,
                                symbolName: componentSymbol(label),
                                isCharging: battery.isCharging,
                                diameter: 54)
            } else {
                BatteryGlyphView(percent: battery.percent, isCharging: battery.isCharging, height: 14)
            }
            Text(battery.percent.map { "\($0)%" } ?? "—")
                .font(.caption.monospacedDigit())
        }
    }

    private func componentSymbol(_ label: String) -> String {
        switch label {
        case "Left": return "earbud.left"
        case "Right": return "earbud.right"
        default: return "airpods.chargingcase"
        }
    }
}
