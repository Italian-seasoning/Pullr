import AppKit
import SwiftUI

struct ClipCardView: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ThumbnailPlaceholder(item: item)
                .frame(height: 138)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.uploader ?? item.domain)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    StatusBadge(status: item.status)
                }

                PullrProgressBar(progress: item.progress, status: item.status)

                HStack(spacing: 8) {
                    if let speed = item.speed {
                        Label(speed, systemImage: "speedometer")
                    }
                    if let eta = item.eta {
                        Label(eta, systemImage: "timer")
                    }
                    if item.isPlaylist {
                        Label("Playlist", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(1)
            }

            HStack {
                PresetDropdownView(item: item)

                Spacer()

                if item.status == .waiting {
                    Button {
                        store.startQueue()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Start downloads")
                    .accessibilityLabel("Start downloads")
                } else if store.activeItemIDs.contains(item.id) {
                    Button {
                        item.status == .paused ? store.resume(item) : store.pause(item)
                    } label: {
                        Image(systemName: item.status == .paused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(item.status == .paused ? "Resume download" : "Pause download")
                    .accessibilityLabel("\(item.status == .paused ? "Resume" : "Pause") \(item.displayTitle)")
                }

                if item.status == .waiting || store.activeItemIDs.contains(item.id) {
                    Button {
                        store.cancel(item)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel download")
                    .accessibilityLabel("Cancel \(item.displayTitle)")
                }

                ItemActionsMenu(item: item, showLogs: $showLogs)
            }

            if let error = item.errorMessage, item.status == .failed || item.status == .cancelled {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(item.status == .failed ? AppTheme.danger : AppTheme.warning)
                    .lineLimit(2)
            }

            if showLogs {
                LogPreview(logs: item.logs)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: 18, selected: store.activeItemIDs.contains(item.id))
    }
}

struct ThumbnailPlaceholder: View {
    var item: DownloadItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.thumbnailFill)
                    .overlay {
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.16), .white.opacity(0.04), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                if let thumbnailURL = item.thumbnailURL, let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                                .overlay {
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.52)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                }
                        case .failure:
                            thumbnailFallback
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        case .empty:
                            thumbnailFallback
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .opacity(0.72)
                        @unknown default:
                            thumbnailFallback
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                } else {
                    thumbnailFallback
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                VStack {
                    Spacer()
                    HStack {
                        Label(item.isPlaylist ? playlistLabel : item.domain, systemImage: item.isPlaylist ? "list.bullet.rectangle" : "play.rectangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.glassTint.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private var thumbnailFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: item.isPlaylist ? "rectangle.stack" : "play.rectangle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(AppTheme.subtleAccent)
            Text(item.domain)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.secondaryText)
    }

    private var playlistLabel: String {
        if let count = item.playlistEntryCount, count > 0 {
            return "\(count) videos"
        }
        return "Playlist"
    }
}

struct ItemActionsMenu: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem
    @Binding var showLogs: Bool

    var body: some View {
        Menu {
            Button("Open in Finder") {
                store.openInFinder(path: item.outputPath)
            }
            .disabled(item.outputPath == nil)

            Button(showLogs ? "Hide Logs" : "Show Logs") {
                showLogs.toggle()
            }
            .disabled(item.logs.isEmpty)

            Button("Open Full Log") {
                store.openDiagnosticLog(for: item)
            }

            Button("Refresh Metadata") {
                store.refreshMetadata(for: item)
            }

            if store.activeItemIDs.contains(item.id) {
                Button(item.status == .paused ? "Resume" : "Pause") {
                    item.status == .paused ? store.resume(item) : store.pause(item)
                }
            }

            if item.isPlaylist {
                Button(store.expandingPlaylistIDs.contains(item.id) ? "Expanding Playlist..." : "Expand Playlist") {
                    store.expandPlaylist(item)
                }
                .disabled(store.expandingPlaylistIDs.contains(item.id))
            }

            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url, forType: .string)
            }

            Divider()

            Button(item.status.isTerminal ? "Remove" : "Cancel") {
                item.status.isTerminal ? store.remove(item) : store.cancel(item)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .help("More actions")
        .accessibilityLabel("More actions for \(item.displayTitle)")
    }
}

struct LogPreview: View {
    var logs: [String]

    var body: some View {
        ScrollView {
            Text(logs.suffix(40).joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 130)
        .padding(8)
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}
