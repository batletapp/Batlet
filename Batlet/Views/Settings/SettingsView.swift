import SwiftUI

enum SettingsAppearance {
    static let background = Color(nsColor: .underPageBackgroundColor)
}

/// The Preferences window with General, Notifications, Devices, and About tabs.
struct SettingsView: View {
    static let windowSize = CGSize(width: 500, height: 540)
    let onAddDevice: () -> Void

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            DevicesSettingsView(onAddDevice: onAddDevice)
                .tabItem { Label("Devices", systemImage: "ipodtouch") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(SettingsAppearance.background)
    }
}
