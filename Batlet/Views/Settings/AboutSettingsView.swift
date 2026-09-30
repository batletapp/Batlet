import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            AppGlyph(size: 84)
            Text("Batlet").font(.title.bold())
            Text("Your batteries, at a glance.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("Free to use. See the battery levels of your Mac, AirPods, and Bluetooth devices from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .background(SettingsAppearance.background)
    }
}
