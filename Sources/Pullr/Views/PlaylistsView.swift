import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var store: AppStore

    private var playlistItems: [DownloadItem] {
        store.items.filter(\.isPlaylist)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.seasonPlan?.title ?? "Season Capture")
                        .font(.callout.weight(.semibold))
                    Text(seasonSummary)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Button("Manage Season") {
                    store.presentSeasonManager()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(store.seasonPlan == nil)
            }
            .padding(14)
            .glassPanel(cornerRadius: 16, material: .thinMaterial)

            if playlistItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Playlist links will appear here.")
                        .font(.title3.weight(.semibold))
                    Text("Add a YouTube playlist URL from the clipboard or paste sheet.")
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 22)
            } else {
                ClipListView(items: playlistItems)
            }
        }
    }

    private var seasonSummary: String {
        guard let plan = store.seasonPlan else {
            return "Capture an episode, then choose Plan season."
        }
        let selected = plan.episodes.filter(\.isSelected)
        return "\(selected.filter { $0.capturedURL != nil }.count)/\(selected.count) captured · \(plan.quality.title)"
    }
}
