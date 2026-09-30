import SwiftUI

/// A single device row: icon, name, trailing percentage and battery glyph.
struct DeviceRow: View {
    @EnvironmentObject private var settings: AppSettings
    let device: Device
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 10) {
                DeviceIconView(kind: device.kind, size: 18)
                    .frame(width: 24)

                Text(settings.displayName(for: device))
                    .font(.callout)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let percent = device.overallPercent {
                    Text("\(percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                BatteryGlyphView(percent: device.overallPercent,
                                 isCharging: device.overallPercent != nil && device.isCharging,
                                 isConnectedToPower: device.overallPercent != nil && device.isConnectedToPower)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
    }
}

/// Circle layout for a connected device in the dashboard.
struct DeviceCircleTile: View {
    @EnvironmentObject private var settings: AppSettings
    let device: Device
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: 3) {
                BatteryRingView(percent: device.overallPercent,
                                symbolName: device.kind.symbolName,
                                deviceKind: device.kind,
                                isCharging: device.isCharging,
                                isConnectedToPower: device.isConnectedToPower,
                                diameter: 46)
                Text(device.overallPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(settings.displayName(for: device))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.displayName(for: device))
    }
}
