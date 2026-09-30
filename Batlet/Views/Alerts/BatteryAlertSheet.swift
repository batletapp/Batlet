import SwiftUI

/// Per-device battery alert configuration, opened from the Devices tab (or a right-click in
/// the Dashboard). Alerts are configured per device.
struct BatteryAlertSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let device: Device
    @State private var draft: BatteryAlert
    @State private var previewResult: BatteryPreviewResult?
    @State private var isPreviewing = false
    @State private var showSoundChoices = false

    init(device: Device, existing: BatteryAlert?) {
        self.device = device
        _draft = State(initialValue: existing ?? BatteryAlert(
            deviceKey: device.id,
            deviceName: device.name,
            kind: device.kind
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DeviceIconView(kind: device.kind, size: 24)
                VStack(alignment: .leading) {
                    Text("Battery Alerts").font(.headline)
                    Text(settings.displayName(for: device)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)

            Form {
                Section {
                    Toggle("Low battery alert", isOn: $draft.lowEnabled)
                    if draft.lowEnabled {
                        HStack {
                            Text("Notify at")
                            Slider(value: Binding(
                                get: { Double(draft.lowThreshold) },
                                set: { draft.lowThreshold = Int($0) }
                            ), in: 5...50, step: 5)
                            Text("\(draft.lowThreshold)%").monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                    }
                }
                Section {
                    Toggle("Fully charged alert", isOn: $draft.chargedEnabled)
                }
                Section {
                    Picker("Style", selection: $draft.style) {
                        ForEach(AlertStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    Toggle("Play sound", isOn: $draft.playSound)
                    if draft.playSound {
                        HStack {
                            Text("Sound")
                            Spacer()
                            Button {
                                showSoundChoices = true
                            } label: {
                                HStack(spacing: 8) {
                                    Text(draft.selectedSound.label)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                }
                                .frame(width: 164, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .popover(isPresented: $showSoundChoices) {
                                soundChoices
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(isPreviewing ? "Sending…" : "Preview") {
                    let kind = device.kind
                    let name = settings.displayName(for: device)
                    let threshold = draft.lowThreshold
                    let style = draft.style
                    let playSound = draft.playSound
                    let sound = draft.selectedSound
                    previewResult = nil
                    isPreviewing = true
                    Task { @MainActor in
                        previewResult = await BatteryAlertManager.shared.preview(
                            kind: kind, name: name, threshold: threshold,
                            style: style, playSound: playSound, sound: sound
                        )
                        isPreviewing = false
                    }
                }
                .disabled(isPreviewing)
                if settings.alert(for: device.id) != nil {
                    Button("Remove", role: .destructive) {
                        settings.removeAlert(for: device.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if settings.systemNotificationsEnabled && draft.style == .notification
                        && (draft.lowEnabled || draft.chargedEnabled) {
                        PermissionsManager.shared.requestNotifications()
                    }
                    settings.upsert(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

            if let previewResult, let message = previewResult.message {
                VStack(alignment: .leading, spacing: 4) {
                    Label(message, systemImage: "info.circle")
                    if previewResult.needsSystemSettings {
                        Button("Open Notification Settings") {
                            PermissionsManager.openNotificationSettings()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private var soundChoices: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose a sound")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(AlertSound.allCases) { sound in
                HStack(spacing: 8) {
                    Button {
                        draft.selectedSound = sound
                        showSoundChoices = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: draft.selectedSound == sound
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.selectedSound == sound ? Color.accentColor : Color.secondary)
                            Text(sound.label)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        AlertSoundPlayer.shared.play(sound)
                    } label: {
                        Image(systemName: "play.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Play \(sound.label)")
                    .accessibilityLabel("Play \(sound.label)")
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
