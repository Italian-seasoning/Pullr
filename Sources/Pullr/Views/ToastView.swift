import SwiftUI

struct ToastView: View {
    var toast: ToastMessage

    var body: some View {
        Label(toast.message, systemImage: iconName)
            .font(.callout)
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassPanel(cornerRadius: 14, material: .thinMaterial)
            .frame(maxWidth: 420, alignment: .trailing)
            .accessibilityLabel(toast.message)
    }

    private var iconName: String {
        switch toast.kind {
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .info: "info.circle"
        }
    }
}
