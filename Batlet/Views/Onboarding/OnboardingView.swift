import SwiftUI
import CoreBluetooth
import UserNotifications

/// First-run flow: Welcome -> setup. Bluetooth access is required to finish.
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var permissions: PermissionsManager

    /// Called when onboarding finishes so the app can begin scanning and close the window.
    var onFinish: () -> Void

    private enum Step {
        case welcome, setup
    }
    @State private var step: Step = .welcome
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            Divider()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
        .frame(width: 500, height: 590)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .alert("Couldn’t update Launch at Login", isPresented: $launchAtLoginError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can enable it later in Batlet Settings or macOS System Settings.")
        }
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .setup: setupStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            AppGlyph(size: 96)
            VStack(spacing: 6) {
                Text("Welcome to Batlet").font(.largeTitle.bold())
                Text("Your batteries, at a glance.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("See the battery of your AirPods and nearby Bluetooth devices right from the menu bar, with low-battery alerts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            Spacer()
            Text("Free to use.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var setupStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stepHeader(title: "Set up Batlet",
                           subtitle: "Bluetooth is required. The other options can be enabled later.")
                PermissionStepView(
                    symbol: "dot.radiowaves.left.and.right",
                    title: "Bluetooth",
                    description: "Required to read AirPods and Bluetooth battery levels.",
                    status: bluetoothStatus,
                    actionTitle: bluetoothStatus == .granted ? nil :
                        (permissions.bluetooth == .notDetermined ? "Grant Access" : "Open Settings"),
                    action: {
                        if permissions.bluetooth == .notDetermined {
                            permissions.requestBluetooth()
                        } else {
                            PermissionsManager.openBluetoothSettings()
                        }
                    }
                )
                if permissions.bluetooth == .denied || permissions.bluetooth == .restricted {
                    Text("Enable Bluetooth access in System Settings, then click Recheck.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Recheck") { permissions.refresh() }
                        .controlSize(.small)
                }
                PermissionStepView(
                    symbol: "bell.badge",
                    title: "Notifications",
                    description: "Optional alerts for low and fully charged batteries.",
                    status: notificationStatus,
                    actionTitle: notificationStatus == .granted ? nil :
                        (permissions.notifications == .notDetermined ? "Grant Access" : "Open Settings"),
                    action: {
                        if permissions.notifications == .notDetermined {
                            permissions.requestNotifications()
                        } else {
                            PermissionsManager.openNotificationSettings()
                        }
                    }
                )
                PermissionStepView(
                    symbol: "power",
                    title: "Launch at Login",
                    description: "Optional. Open Batlet automatically when you log in.",
                    status: launchAtLogin ? .granted : .disabled,
                    statusLabel: launchAtLogin ? "Enabled" : "Off",
                    actionTitle: launchAtLogin ? "Disable" : "Enable",
                    action: {
                        if !LaunchAtLogin.setEnabled(!launchAtLogin) {
                            launchAtLoginError = true
                        }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        switch step {
        case .welcome:
            VStack(spacing: 10) {
                Button(action: { step = .setup; permissions.refresh() }) {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                Text("By continuing, you agree to use this at your own discretion.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .setup:
            HStack {
                Button("Back") { step = .welcome }
                Spacer()
                Button("Complete") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!permissions.bluetoothGranted)
            }
        }
    }

    // MARK: - Status mapping

    private var bluetoothStatus: PermissionStepView.Status {
        switch permissions.bluetooth {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private var notificationStatus: PermissionStepView.Status {
        switch permissions.notifications {
        case .authorized, .provisional, .ephemeral: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func finish() {
        permissions.refresh()
        guard permissions.bluetoothGranted else { return }
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}

/// A simple stand-in for the app icon until a real asset is added.
struct AppGlyph: View {
    var size: CGFloat = 64
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.4, blue: 0.95),
                                          Color(red: 0.35, green: 0.3, blue: 0.85)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.2), radius: size * 0.08, y: size * 0.04)
    }
}
