import SwiftUI

/// A rounded container that keeps a section label and its device rows together.
struct DeviceGroupCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String?
    var titleColor: Color = .secondary
    var count: Int? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.caption2.weight(.medium))
                    if let count {
                        DeviceCountBadge(count: count, color: titleColor)
                    }
                }
                .foregroundStyle(titleColor)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            VStack(spacing: 2) { content }
                .padding(6)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

struct DeviceCountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        let diameter: CGFloat = count > 99 ? 28 : 22
        Text("\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .frame(width: diameter, height: diameter)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityLabel("\(count) devices")
    }
}
