import SwiftUI
import AppKit

struct NotificationsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var permissions = PermissionsManager.shared

    var body: some View {
        Form {
            Section {
                Picker("Alert style", selection: $settings.alertDisplayStyle) {
                    ForEach(AlertDisplayStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose how Batlet shows connection, battery, and nearby-device alerts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            }

            if settings.alertDisplayStyle == .hub {
                Section {
                    Picker("Position", selection: $settings.hubVerticalPosition) {
                        ForEach(HubVerticalPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Direction", selection: $settings.hubHorizontalAlignment) {
                        ForEach(HubHorizontalAlignment.allCases) { alignment in
                            Text(alignment.label).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Hub placement")
                }
            }

            Section {
                Toggle("System notifications", isOn: $settings.systemNotificationsEnabled)

                Text("Allow macOS notifications for battery alerts set to Standard Notification.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if settings.systemNotificationsEnabled {
                    switch permissions.notifications {
                    case .notDetermined:
                        Button("Allow Notifications") {
                            permissions.requestNotifications()
                        }
                    case .denied:
                        notificationSettingsLink("Notifications are disabled for Batlet in macOS Settings.")
                    case .authorized, .provisional, .ephemeral:
                        if permissions.notificationAlertsEnabled == false {
                            notificationSettingsLink("Notification banners are disabled in macOS Settings.")
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } header: {
                Text("macOS notifications")
            }

            Section {
                Button("Preview alert") {
                    AlertPresenter.shared.show(AlertPresentation(
                        title: "AirPods Pro", subtitle: "Connected successfully",
                        symbol: "airpodspro", percent: 100, tone: .success,
                        deviceImageName: "ConnectionAirPods", isConnectionEvent: true
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.background)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onChange(of: settings.systemNotificationsEnabled) { _, enabled in
            if enabled && permissions.notifications == .notDetermined {
                permissions.requestNotifications()
            }
        }
    }

    private func notificationSettingsLink(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open macOS Notification Settings") {
                PermissionsManager.openNotificationSettings()
            }
            .buttonStyle(.link)
        }
    }
}
