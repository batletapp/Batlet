import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Enable and Launch at Login")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }
                Text("Batlet runs in the background so it can show battery info and deliver alerts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeading("Enable Batlet")
            }

            Section {
                Toggle("Automatic check for updates", isOn: $settings.automaticUpdateChecksEnabled)
            } header: {
                sectionHeading("Updates")
            }

            Section {
                Toggle("Suggest known devices in the background", isOn: $settings.nearbyPromptsEnabled)
                Text("Shows prompts for previously paired devices when Batlet notices them. Use Add Device to scan for new devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeading("Nearby Devices")
            }

            Section {
                menuBarIconPicker
                Toggle("Badge count", isOn: $settings.showMenuBarBadgeCount)
                Text("Total of connected devices")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeading("Menu Bar Icon")
            }

            Section {
                HStack(spacing: 12) {
                    Text("Battery display type")
                    Spacer(minLength: 8)
                    Picker("Battery display type", selection: $settings.batteryDisplayType) {
                        ForEach(BatteryDisplayType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 176)
                }

                HStack(spacing: 12) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview")
                            .font(.subheadline.weight(.medium))
                        Text("AirPods Pro · 64%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    batteryDisplayPreview
                        .frame(width: 72, height: 48)
                        .accessibilityLabel("Battery display preview, 64 percent")
                }
                .padding(.vertical, 4)
            } header: {
                sectionHeading("Appearance")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.background)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
    }

    @ViewBuilder
    private var batteryDisplayPreview: some View {
        switch settings.batteryDisplayType {
        case .circle:
            BatteryRingView(
                percent: 64,
                symbolName: "airpodspro",
                diameter: 42
            )
        case .bar:
            BatteryGlyphView(
                percent: 64,
                height: 16,
                tint: .green
            )
        }
    }

    private var menuBarIconPicker: some View {
        HStack(spacing: 8) {
            ForEach(MenuBarIconStyle.allCases) { style in
                iconTile(style)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconTile(_ style: MenuBarIconStyle) -> some View {
        let selected = settings.menuBarIconStyle == style
        return Button {
            settings.menuBarIconStyle = style
        } label: {
            VStack(spacing: 6) {
                Image(systemName: style.symbolName)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                Text(style.label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

}
