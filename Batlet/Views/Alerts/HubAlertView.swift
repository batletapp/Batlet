import SwiftUI

/// Compact popup used at a screen edge when Hub is selected in Notifications.
struct HubAlertView: View {
    static let width: CGFloat = 320

    static func height(for alert: AlertPresentation) -> CGFloat {
        alert.primaryAction == nil ? 98 : 138
    }

    let alert: AlertPresentation
    let onDismiss: () -> Void
    var onPrimaryAction: (() -> Void)? = nil

    private var batteryColor: Color {
        switch alert.batteryLevel {
        case .healthy: .green
        case .low: .orange
        case .critical: .red
        case nil: .secondary
        }
    }

    var body: some View {
        content
            .foregroundStyle(.white)
            .background { AlertGlassSurface(cornerRadius: 42) }
            .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            AlertDismissButton(action: onDismiss).padding(12)
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                artwork

                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)

                    Text(alert.subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    if let percent = alert.percent {
                        HStack(spacing: 5) {
                            Text("\(percent)%")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            BatteryGlyphView(percent: percent, isCharging: alert.isCharging,
                                             height: 12, tint: batteryColor)
                            if alert.recommendsCharging {
                                Text("Charge soon")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .foregroundStyle(batteryColor)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Battery \(percent) percent")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 34)

            if alert.primaryAction != nil {
                HStack(spacing: 8) {
                    Button("Ignore", action: onDismiss)
                        .buttonStyle(.bordered)
                    Button("Connect") { onPrimaryAction?() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: Self.width, height: Self.height(for: alert))
    }

    @ViewBuilder private var artwork: some View {
        if let imageName = alert.deviceImageName {
            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 56)
                .accessibilityHidden(true)
        } else {
            Image(systemName: alert.symbol)
                .font(.system(size: 27, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 48, height: 56)
                .accessibilityHidden(true)
        }
    }

}
