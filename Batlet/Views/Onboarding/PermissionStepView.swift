import SwiftUI

/// A reusable onboarding row with its current status and primary action.
struct PermissionStepView: View {
    enum Status {
        case notDetermined, granted, denied, disabled

        var color: Color {
            switch self {
            case .notDetermined: return .secondary
            case .granted: return .green
            case .denied: return .orange
            case .disabled: return .secondary
            }
        }
        var symbol: String {
            switch self {
            case .notDetermined: return "circle.dashed"
            case .granted: return "checkmark.circle.fill"
            case .denied: return "exclamationmark.triangle.fill"
            case .disabled: return "circle"
            }
        }
        var label: String {
            switch self {
            case .notDetermined: return "Not requested"
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .disabled: return "Off"
            }
        }
    }

    let symbol: String
    let title: String
    let description: String
    let status: Status
    var statusLabel: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: status.symbol)
                        Text(statusLabel ?? status.label)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(status.color)
                    Spacer(minLength: 8)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
