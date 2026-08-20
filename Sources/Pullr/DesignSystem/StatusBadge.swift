import SwiftUI

struct StatusBadge: View {
    var status: DownloadStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(foreground.opacity(0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(foreground.opacity(0.20), lineWidth: 0.5)
            }
            .accessibilityLabel("Status: \(status.title)")
    }

    private var foreground: Color {
        switch status {
        case .completed:
            AppTheme.success
        case .failed:
            AppTheme.danger
        case .cancelled:
            AppTheme.warning
        case .downloading, .converting:
            AppTheme.subtleAccent
        case .paused:
            AppTheme.warning
        case .waiting, .fetchingInfo:
            AppTheme.secondaryText
        }
    }
}

struct PullrProgressBar: View {
    var progress: Double
    var status: DownloadStatus

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppTheme.panelStroke.opacity(0.42))

                Capsule(style: .continuous)
                    .fill(fillColor)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 6)
        .animation(.pullrMicro, value: progress)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private var fillColor: Color {
        switch status {
        case .failed:
            AppTheme.danger
        case .cancelled:
            AppTheme.warning
        case .paused:
            AppTheme.warning
        case .completed:
            AppTheme.success
        default:
            AppTheme.subtleAccent
        }
    }
}
