import SwiftUI
import AppKit

/// The content shown in the system menu bar, driven by the user's icon-style preference.
struct MenuBarLabel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: DeviceStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let count = settings.visibleConnectedDeviceCount(in: store.devices)
        let badgeCount = settings.menuBarBadgeCount(in: store.devices)
        let renderer = ImageRenderer(content: MenuBarIconArtwork(style: settings.menuBarIconStyle, count: badgeCount, colorScheme: colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return Image(nsImage: renderer.nsImage ?? NSImage())
            .renderingMode(.original)
            .accessibilityLabel("Batlet, \(count) connected \(count == 1 ? "device" : "devices")")
    }
}

/// MenuBarExtra turns separate images and text into adjacent status-item content.
/// Rendering this artwork as one image keeps the count overlapping the selected symbol.
struct MenuBarIconArtwork: View {
    var style: MenuBarIconStyle = .appIcon
    let count: Int
    let colorScheme: ColorScheme

    private var iconColor: Color { colorScheme == .dark ? .white : .black }
    private var badgeWidth: CGFloat { count > 99 ? 22 : count > 9 ? 17 : 13 }
    private let badgeHeight: CGFloat = 12
    private let artworkHeight: CGFloat = 18

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: style.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(iconColor)
                .frame(width: 17, height: 17)
                .position(x: 8.5, y: 8.5)

            if count > 0 {
                Capsule()
                    .fill(iconColor)
                    .frame(width: badgeWidth, height: badgeHeight)
                    .position(x: 10 + badgeWidth / 2, y: artworkHeight - badgeHeight / 2)

                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: badgeWidth, height: badgeHeight)
                    .position(x: 10 + badgeWidth / 2, y: artworkHeight - badgeHeight / 2)
                    .blendMode(.destinationOut)
            }
        }
        .frame(width: count > 0 ? 10 + badgeWidth : 17, height: count > 0 ? artworkHeight : 17)
        .compositingGroup()
    }
}
