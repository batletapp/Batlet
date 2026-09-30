import SwiftUI

/// A compact horizontal battery indicator with a colored level, charging bolt,
/// or an in-shell N/A label when the level is unavailable.
struct BatteryGlyphView: View {
    var percent: Int?
    var isCharging: Bool = false
    var isConnectedToPower: Bool = false
    var height: CGFloat = 12
    var lowThreshold: Int = 20
    var tint: Color? = nil

    private var width: CGFloat { height * 1.9 }

    private var fillColor: Color {
        guard let percent else { return .secondary.opacity(0.4) }
        if let tint { return tint }
        if isCharging || isConnectedToPower { return .green }
        return percent <= lowThreshold ? .red : .green
    }

    private var fraction: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    var body: some View {
        HStack(spacing: height * 0.12) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.28)
                    .stroke(.secondary.opacity(0.7), lineWidth: max(1, height * 0.09))
                    .frame(width: width, height: height)

                if percent == nil {
                    RoundedRectangle(cornerRadius: height * 0.18)
                        .fill(.secondary.opacity(0.16))
                        .frame(width: width - height * 0.28, height: height - height * 0.28)
                        .padding(.leading, height * 0.14)

                    Text("N/A")
                        .font(.system(size: height * 0.6, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: width, height: height)
                } else {
                    RoundedRectangle(cornerRadius: height * 0.18)
                        .fill(fillColor)
                        .frame(width: max(0, (width - height * 0.28) * fraction), height: height - height * 0.34)
                        .padding(.leading, height * 0.14)
                }

                if isConnectedToPower || isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 1.5, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.55))
                        .scaleEffect(x: 1, y: 0.7)
                        .shadow(color: .black.opacity(0.65), radius: 1)
                        .frame(width: width, height: height)
                }
            }
            // Battery tip
            RoundedRectangle(cornerRadius: height * 0.1)
                .fill(.secondary.opacity(0.7))
                .frame(width: height * 0.1, height: height * 0.4)
        }
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let level = percent.map { "Battery \($0) percent" } ?? "Battery level unavailable"
        if isConnectedToPower { return "\(level), connected to power" }
        if isCharging { return "\(level), charging" }
        return level
    }
}

/// Device icon inside a circular battery progress ring.
struct BatteryRingView: View {
    var percent: Int?
    var symbolName: String
    var deviceKind: DeviceKind? = nil
    var isCharging: Bool = false
    var isConnectedToPower: Bool = false
    var diameter: CGFloat = 68
    var lowThreshold: Int = 20

    private var fraction: CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(100, max(0, percent))) / 100
    }

    private var progressColor: Color {
        guard let percent else { return .secondary }
        return percent <= lowThreshold ? .red : .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.22), lineWidth: diameter * 0.12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(progressColor, style: StrokeStyle(lineWidth: diameter * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let deviceKind {
                DeviceIconView(kind: deviceKind, size: diameter * 0.40)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: diameter * 0.34, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: diameter * 0.62, height: diameter * 0.62)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if isCharging || isConnectedToPower {
                Image(systemName: "bolt.fill")
                    .font(.system(size: diameter * 0.19, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(2)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: diameter * 0.04, y: -diameter * 0.07)
            }
        }
        .accessibilityLabel(percent.map { "Battery \($0) percent" } ?? "Battery level unavailable")
    }
}
