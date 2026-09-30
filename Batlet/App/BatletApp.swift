import SwiftUI
import AppKit
import UserNotifications

@main
struct BatletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var store = DeviceStore.shared
    @StateObject private var permissions = PermissionsManager.shared

    private var menuBarIconIsInserted: Binding<Bool> {
        Binding(
            get: { settings.hasCompletedOnboarding && permissions.bluetoothGranted },
            set: { _ in }
        )
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconIsInserted) {
            DashboardView(onOpenSettings: { appDelegate.showSettings() },
                          onAddDevice: { appDelegate.showAddDevice() })
                .environmentObject(settings)
                .environmentObject(store)
        } label: {
            MenuBarLabel(settings: settings, store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Coordinates first-run onboarding and the app lifecycle. The app is a menu bar agent
/// (LSUIElement), so onboarding and Settings temporarily switch to a regular
/// activation policy to present a Dock icon and a focusable window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var addDeviceWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView(onAddDevice: { [weak self] in self?.showAddDevice() })
                .environmentObject(AppSettings.shared)
                .environmentObject(DeviceStore.shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Batlet Settings"
            window.delegate = self
            window.contentMinSize = SettingsView.windowSize
            window.contentViewController = NSHostingController(rootView: root)
            window.setContentSize(SettingsView.windowSize)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showAddDevice() {
        if addDeviceWindow == nil {
            let root = AddDeviceView()
                .environmentObject(DeviceStore.shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: AddDeviceView.windowSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "Add Device"
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: root)
            window.contentMinSize = AddDeviceView.windowSize
            window.setContentSize(AddDeviceView.windowSize)
            window.isReleasedWhenClosed = false
            window.center()
            addDeviceWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        addDeviceWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        let permissions = PermissionsManager.shared
        permissions.refresh()
        UNUserNotificationCenter.current().delegate = self

        if !settings.hasCompletedOnboarding || permissions.bluetooth != .allowedAlways {
            showOnboarding()
        } else {
            startServices()
        }
    }

    private func startServices() {
        ConnectionAlertManager.shared.start(store: .shared, settings: .shared)
        DeviceStore.shared.start()
        NearbyDeviceManager.shared.start(store: .shared, settings: .shared)
        BatteryAlertManager.shared.start(store: .shared, settings: .shared)
    }

    private func showOnboarding() {
        guard onboardingWindow == nil else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let root = OnboardingView(onFinish: { [weak self] in self?.finishOnboarding() })
            .environmentObject(AppSettings.shared)
            .environmentObject(PermissionsManager.shared)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to Batlet"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        NSApp.setActivationPolicy(.accessory)
        startServices()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        if (notification.object as? NSWindow) === addDeviceWindow {
            NearbyDeviceManager.shared.stopScan()
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
}
