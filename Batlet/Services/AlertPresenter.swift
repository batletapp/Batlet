import SwiftUI
import AppKit

/// Presents all Batlet popups through one non-activating panel. Alerts
/// queue so simultaneous connections or battery events do not replace one another.
@MainActor
final class AlertPresenter {
    static let shared = AlertPresenter()

    private let settings: AppSettings
    private var panel: NSPanel?
    private var activeAlert: AlertPresentation?
    private var activeStyle: AlertDisplayStyle = .alertBox
    private var activeVerticalPosition: HubVerticalPosition = .top
    private var activeHorizontalAlignment: HubHorizontalAlignment = .center
    private var dismissWorkItem: DispatchWorkItem?
    private var pending: [AlertPresentation] = []

    var currentPanel: NSPanel? { panel }

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func show(_ alert: AlertPresentation) {
        pending.append(alert)
        showNextIfNeeded()
    }

    func removeNearbyPrompt(for address: String) {
        pending.removeAll { $0.nearbyDeviceAddress == address }
        if activeAlert?.nearbyDeviceAddress == address { dismiss() }
    }

    func removeAllNearbyPrompts() {
        pending.removeAll { $0.nearbyDeviceAddress != nil }
        if activeAlert?.nearbyDeviceAddress != nil { dismiss() }
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        activeAlert = nil
        showNextIfNeeded()
    }

    func updateConnectionBattery(for deviceID: String, percent: Int, isCharging: Bool) {
        guard (0...100).contains(percent) else { return }
        for index in pending.indices where pending[index].connectionDeviceID == deviceID {
            pending[index].percent = percent
            pending[index].isCharging = isCharging
        }

        guard var alert = activeAlert, alert.connectionDeviceID == deviceID,
              alert.percent != percent || alert.isCharging != isCharging
        else { return }
        alert.percent = percent
        alert.isCharging = isCharging
        activeAlert = alert
        switch activeStyle {
        case .alertBox:
            (panel?.contentView as? NSHostingView<CenteredAlertView>)?.rootView = makeCenteredContent(for: alert)
        case .hub:
            (panel?.contentView as? NSHostingView<HubAlertView>)?.rootView = makeHubContent(for: alert)
        }
        resizePanel(for: alert)
    }

    private func resizePanel(for alert: AlertPresentation) {
        guard let panel else { return }
        let height = activeStyle == .hub ? HubAlertView.height(for: alert) : CenteredAlertView.height(for: alert)
        guard panel.frame.height != height else { return }
        let size = CGSize(width: panel.frame.width, height: height)
        let frame = Self.frame(for: size, in: panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame,
                               style: activeStyle, vertical: activeVerticalPosition,
                               horizontal: activeHorizontalAlignment)
        panel.setFrame(frame, display: true)
    }

    private func showNextIfNeeded() {
        guard panel == nil else { return }
        pending.removeAll { $0.expiresAt.map { $0 <= Date() } ?? false }
        guard !pending.isEmpty else { return }
        let alert = pending.removeFirst()
        activeAlert = alert
        activeStyle = settings.alertDisplayStyle
        activeVerticalPosition = settings.hubVerticalPosition
        activeHorizontalAlignment = settings.hubHorizontalAlignment

        let size: CGSize
        let contentView: NSView
        switch activeStyle {
        case .alertBox:
            size = CGSize(width: CenteredAlertView.width, height: CenteredAlertView.height(for: alert))
            contentView = NSHostingView(rootView: makeCenteredContent(for: alert))
        case .hub:
            size = CGSize(width: HubAlertView.width, height: HubAlertView.height(for: alert))
            contentView = NSHostingView(rootView: makeHubContent(for: alert))
        }
        contentView.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: contentView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = contentView
        panel.ignoresMouseEvents = false

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main {
            panel.setFrame(Self.frame(for: size, in: screen.visibleFrame,
                                      style: activeStyle, vertical: activeVerticalPosition,
                                      horizontal: activeHorizontalAlignment), display: false)
        }

        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + alert.autoDismiss, execute: work)
    }

    static func frame(for size: CGSize, in visibleFrame: NSRect, style: AlertDisplayStyle,
                      vertical: HubVerticalPosition, horizontal: HubHorizontalAlignment) -> NSRect {
        guard style == .hub else {
            return NSRect(x: visibleFrame.midX - size.width / 2,
                          y: visibleFrame.midY - size.height / 2,
                          width: size.width, height: size.height)
        }

        let margin: CGFloat = 16
        let x: CGFloat
        switch horizontal {
        case .left: x = visibleFrame.minX + margin
        case .center: x = visibleFrame.midX - size.width / 2
        case .right: x = visibleFrame.maxX - size.width - margin
        }
        let y = vertical == .top
            ? visibleFrame.maxY - size.height - margin
            : visibleFrame.minY + margin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func makeCenteredContent(for alert: AlertPresentation) -> CenteredAlertView {
        CenteredAlertView(alert: alert, onDismiss: { [weak self] in self?.dismiss() },
                          onPrimaryAction: { [weak self] in
            self?.dismiss()
            alert.primaryAction?()
        })
    }

    private func makeHubContent(for alert: AlertPresentation) -> HubAlertView {
        HubAlertView(alert: alert, onDismiss: { [weak self] in self?.dismiss() },
                     onPrimaryAction: { [weak self] in
            self?.dismiss()
            alert.primaryAction?()
        })
    }
}
