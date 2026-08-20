import SwiftUI

struct ClipRowView: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 13) {
                ThumbnailPlaceholder(item: item)
                    .frame(width: 84, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.displayTitle)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(item.domain)
                        if let speed = item.speed {
                            Text(speed)
                        }
                        if let eta = item.eta {
                            Text("ETA \(eta)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                }

                Spacer()

                StatusBadge(status: item.status)
                    .frame(width: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    PullrProgressBar(progress: item.progress, status: item.status)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                .frame(width: 130)

                PresetDropdownView(item: item)
                    .frame(width: 150)

                ItemActionsMenu(item: item, showLogs: $showLogs)
            }

            if showLogs {
                LogPreview(logs: item.logs)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14, material: .thinMaterial, selected: store.activeItemIDs.contains(item.id))
    }
}
