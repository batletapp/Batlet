import SwiftUI

/// Shared popup layout for connection and battery events.
struct CenteredAlertView: View {
    static let width: CGFloat = 360
    static let height: CGFloat = 128

    static func height(for alert: AlertPresentation) -> CGFloat {
        guard alert.isConnectionEvent else { return height }
        if alert.primaryAction != nil { return alert.percent == nil ? 278 : 306 }
        if alert.recommendsCharging { return 284 }
        return alert.percent == nil ? 236 : 264
    }

    let alert: AlertPresentation
    let onDismiss: () -> Void
    var onPrimaryAction: (() -> Void)? = nil

    private var batteryColor: Color {
        switch alert.batteryLevel {
        case .healthy:
            Color(red: 0.72, green: 0.95, blue: 0.79)
        case .low:
            Color(red: 1, green: 0.82, blue: 0.54)
        case .critical:
            Color(red: 1, green: 0.69, blue: 0.67)
        case nil: .primary
        }
    }

    var body: some View {
        content
            .foregroundStyle(.white)
            .background { AlertGlassSurface(cornerRadius: 28) }
            .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            AlertDismissButton(action: onDismiss).padding(14)
        }
    }

    @ViewBuilder private var content: some View {
        if alert.isConnectionEvent {
            VStack(spacing: 0) {
                deviceArtwork(width: 260, height: 116, symbolSize: 64)
                    .padding(.bottom, 8)
                details(centered: true)
            }
            .padding(.horizontal, 22)
            .frame(width: Self.width, height: Self.height(for: alert))
        } else {
            HStack(spacing: 12) {
                deviceArtwork(width: 76, height: 78, symbolSize: 44)
                details(centered: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 40)
            }
            .padding(.horizontal, 22)
            .frame(width: Self.width, height: Self.height)
        }
    }

    private func details(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 3) {
            Text(alert.title)
                .font(.system(size: centered ? 21 : 18, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(centered ? .center : .leading)

            Text(alert.subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.68))

            if let percent = alert.percent {
                batteryStatus(percent: percent)
                    .padding(.top, centered ? 8 : 3)
            }

            if alert.primaryAction != nil {
                HStack(spacing: 10) {
                    Button("Ignore", action: onDismiss)
                        .buttonStyle(.bordered)
                    Button("Connect") { onPrimaryAction?() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 14)
            }
        }
    }

    private func batteryStatus(percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("\(percent)%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                BatteryGlyphView(percent: percent, isCharging: alert.isCharging,
                                 height: 14, tint: batteryColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery \(percent) percent")

            if alert.recommendsCharging {
                Text("Connect a charger soon")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(batteryColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func deviceArtwork(width: CGFloat, height: CGFloat,
                                            symbolSize: CGFloat) -> some View {
        if let imageName = alert.deviceImageName {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width, height: height)
                .accessibilityHidden(true)
        } else {
            Image(systemName: alert.symbol)
                .font(.system(size: symbolSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: width, height: height)
                .accessibilityHidden(true)
        }
    }

}
