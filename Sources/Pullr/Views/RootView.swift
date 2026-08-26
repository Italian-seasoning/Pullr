import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDownloadID: UUID?
    @State private var isInspectorPresented = true

    var body: some View {
        ZStack {
            FrostedGlassEffect(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            AppTheme.baseBackground
                .ignoresSafeArea()
            RadialGradient(
                colors: [AppTheme.subtleAccent.opacity(0.13), .clear],
                center: .topLeading,
                startRadius: 24,
                endRadius: 620
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.18, green: 0.42, blue: 0.38).opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 560
            )
            .ignoresSafeArea()

            NavigationSplitView {
                MediaDeskSidebar(selection: $store.selectedSection)
                    .navigationSplitViewColumnWidth(min: 184, ideal: 204, max: 224)
            } detail: {
                GeometryReader { geometry in
                    let inspectorWidth = MediaDeskLayout.inspectorWidth(
                        availableWidth: geometry.size.width,
                        isVisible: isInspectorPresented && store.selectedSection == .downloads
                    )

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ToolbarView(isInspectorPresented: $isInspectorPresented)
                            sectionContent
                            MediaDeskStatusBar()
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

                        if inspectorWidth > 0 {
                            Divider()
                            inspectorContent
                                .frame(width: inspectorWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .pullrPanel, value: isInspectorPresented)
                }
                .background(.clear)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .background(TransparentWindowConfigurator())
        .overlay(alignment: .bottomTrailing) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(20)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .pullrPanel, value: store.selectedSection)
        .animation(reduceMotion ? nil : .pullrPanel, value: store.toast?.id)
        .animation(reduceMotion ? nil : .pullrPanel, value: store.clipboardSuggestion?.id)
        .animation(reduceMotion ? nil : .pullrPanel, value: store.browserCaptureSuggestion?.id)
        .sheet(isPresented: $store.isSeasonManagerPresented) {
            SeasonManagerView()
                .environmentObject(store)
        }
        .task {
            await store.monitorClipboard()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.selectedSection {
        case .downloads:
            MediaDeskDownloadList(selection: $selectedDownloadID)
        case .playlists:
            SectionContainer(title: "Playlists", subtitle: "Review collection links and range defaults") {
                PlaylistsView()
            }
        case .listening:
            SectionContainer(title: "Activity", subtitle: "Optional website and YouTube time stored locally") {
                ListeningHistoryView()
            }
        case .history:
            SectionContainer(title: "History", subtitle: "Completed downloads and saved files") {
                HistoryView()
            }
        case .settings:
            SectionContainer(title: "Settings", subtitle: "Folders, presets, dependencies, and advanced options") {
                SettingsView()
            }
        }
    }

    private var selectedItem: DownloadItem? {
        if let selectedDownloadID,
           let item = store.items.first(where: { $0.id == selectedDownloadID }) {
            return item
        }
        return store.items.first
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if store.selectedSection == .downloads, let selectedItem {
            DownloadInspectorView(item: selectedItem)
                .id(selectedItem.id)
        } else {
            InspectorEmptyState(section: store.selectedSection)
        }
    }
}

private struct MediaDeskSidebar: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .navigationTitle("Pullr")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.dependencyReport.isReady ? AppTheme.success : AppTheme.warning)
                    .frame(width: 7, height: 7)
                Text(store.dependencyReport.isReady ? "Ready to pull" : "Setup required")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct MediaDeskDownloadList: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "Downloads",
                subtitle: "Singles, streams, playlists, and seasons",
                trailing: store.queueSummary
            )

            if store.items.isEmpty {
                MediaDeskEmptyState()
            } else {
                List(selection: $selection) {
                    if !standaloneItems.isEmpty {
                        Section("Inbox") {
                            ForEach(standaloneItems) { item in
                                DownloadListRow(item: item)
                                    .tag(item.id)
                            }
                        }
                    }

                    ForEach(collectionTitles, id: \.self) { title in
                        let items = collectionItems(named: title)
                        Section {
                            ForEach(items) { item in
                                DownloadListRow(item: item)
                                    .tag(item.id)
                            }
                        } header: {
                            CollectionHeader(title: title, items: items)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var standaloneItems: [DownloadItem] {
        store.items.filter { $0.sourcePlaylistTitle?.isEmpty != false }
    }

    private var collectionTitles: [String] {
        var seen = Set<String>()
        return store.items.compactMap { item in
            guard let title = item.sourcePlaylistTitle, !title.isEmpty, seen.insert(title).inserted else {
                return nil
            }
            return title
        }
    }

    private func collectionItems(named title: String) -> [DownloadItem] {
        store.items.filter { $0.sourcePlaylistTitle == title }
    }
}

private struct DownloadListRow: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailPlaceholder(item: item)
                .frame(width: 64, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(sourceLabel)
                    if let speed = item.speed { Text(speed) }
                    if let eta = item.eta { Text("ETA \(eta)") }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

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

            VStack(alignment: .trailing, spacing: 5) {
                Label(item.status.title, systemImage: item.status.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.status == .failed ? AppTheme.danger : AppTheme.secondaryText)
                    .labelStyle(.titleAndIcon)

                PullrProgressBar(progress: item.progress, status: item.status)
                    .frame(width: 92)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var sourceLabel: String {
        if URLExtractor.isHLSURL(item.url) { return "M3U8 stream" }
        if item.isPlaylist { return item.playlistEntryCount.map { "Playlist · \($0) items" } ?? "Playlist" }
        if let index = item.playlistIndex { return "Episode \(index)" }
        return item.domain
    }
}

private struct CollectionHeader: View {
    var title: String
    var items: [DownloadItem]

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)
            Spacer()
            Text("\(completedCount)/\(items.count)")
                .monospacedDigit()
            ProgressView(value: progress)
                .frame(width: 64)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var completedCount: Int { items.filter { $0.status == .completed }.count }
    private var progress: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.progress).reduce(0, +) / Double(items.count)
    }
}

private struct DownloadInspectorView: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ThumbnailPlaceholder(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 166)

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.displayTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .textSelection(.enabled)

                    Label(sourceLabel, systemImage: sourceIcon)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        StatusBadge(status: item.status)
                        Spacer()
                        Text("\(Int(item.progress * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    PullrProgressBar(progress: item.progress, status: item.status)
                }

                Divider()

                InspectorField(title: "Quality and format") {
                    PresetDropdownView(item: item)
                }

                InspectorField(title: "Save to") {
                    Text(store.settings.downloadFolder)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                if let referrer = item.referrerURL {
                    InspectorField(title: "Captured from") {
                        Text(URL(string: referrer)?.host ?? referrer)
                            .font(.callout)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }

                if item.isPlaylist {
                    Button {
                        store.expandPlaylist(item)
                    } label: {
                        Label(
                            store.expandingPlaylistIDs.contains(item.id) ? "Inspecting collection" : "Choose playlist items",
                            systemImage: "checklist"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.expandingPlaylistIDs.contains(item.id))
                }

                if let error = item.errorMessage,
                   !error.isEmpty,
                   item.status == .failed || item.status == .cancelled {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if item.status == .failed || item.status == .cancelled {
                    Button("Retry download") {
                        store.retry(item)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if item.outputPath != nil {
                    Button("Reveal file") {
                        store.openInFinder(path: item.outputPath)
                    }
                }

                if !item.logs.isEmpty {
                    DisclosureGroup("Activity log") {
                        Text(item.logs.suffix(24).joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }

                Divider()

                Button("Remove download", role: .destructive) {
                    store.remove(item)
                }
            }
            .padding(20)
        }
        .background(AppTheme.glassTint)
        .navigationTitle("Inspector")
    }

    private var sourceLabel: String {
        if URLExtractor.isHLSURL(item.url) { return "M3U8 / HLS stream" }
        if item.isPlaylist { return item.playlistEntryCount.map { "Playlist with \($0) items" } ?? "Playlist" }
        if let title = item.sourcePlaylistTitle { return title }
        return item.domain
    }

    private var sourceIcon: String {
        if URLExtractor.isHLSURL(item.url) { return "dot.radiowaves.left.and.right" }
        if item.isPlaylist || item.sourcePlaylistTitle != nil { return "rectangle.stack" }
        return "link"
    }
}

private struct InspectorField<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.tertiaryText)
            content
        }
    }
}

private struct MediaDeskEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("Ready for a link", systemImage: "arrow.down.to.line.compact")
        } description: {
            Text("Paste a video, playlist, season page, or direct M3U8 link above.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectorEmptyState: View {
    var section: AppSection

    var body: some View {
        ContentUnavailableView {
            Label(section == .downloads ? "Select a download" : section.title, systemImage: section.systemImage)
        } description: {
            Text(section == .downloads ? "Choose an item to view format, destination, progress, and errors." : "Details appear here when this section has a selection.")
        }
        .background(AppTheme.glassTint)
    }
}

private struct SectionContainer<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: title, subtitle: subtitle)
            content
                .padding(16)
        }
    }
}

private struct SectionHeader: View {
    var title: String
    var subtitle: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct MediaDeskStatusBar: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 8) {
            if let suggestion = store.browserCaptureSuggestion {
                LinkSuggestionBanner(
                    icon: "dot.radiowaves.left.and.right",
                    thumbnailURL: store.browserCaptureThumbnailURL,
                    title: "Download detected \(suggestion.formatName) stream?",
                    subtitle: [suggestion.mediaHost, suggestion.pageHost].compactMap { $0 }.joined(separator: " · "),
                    detail: store.browserCaptureProbeSummary,
                    confirmTitle: "Add download",
                    secondaryTitle: "Plan season",
                    dismiss: store.dismissBrowserCapture,
                    secondary: store.beginSeasonCapture,
                    confirm: store.acceptBrowserCapture
                )
            } else if let suggestion = store.clipboardSuggestion {
                LinkSuggestionBanner(
                    icon: URLExtractor.isHLSURL(suggestion.url) ? "dot.radiowaves.left.and.right" : "doc.on.clipboard",
                    title: "Use copied video link?",
                    subtitle: suggestion.source,
                    confirmTitle: "Add download",
                    dismiss: store.dismissClipboardSuggestion,
                    confirm: store.acceptClipboardSuggestion
                )
            }

            HStack(spacing: 8) {
                Text("\(store.activeItemIDs.count) active")
                if let speed = store.items.compactMap(\.speed).first {
                    Text("·")
                    Text(speed)
                }
                Spacer()
                Text("\(store.items.filter { $0.status == .waiting }.count) waiting")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .glassPanel(cornerRadius: 14, material: .ultraThinMaterial)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

private struct LinkSuggestionBanner: View {
    var icon: String
    var thumbnailURL: String? = nil
    var title: String
    var subtitle: String
    var detail: String? = nil
    var confirmTitle: String
    var secondaryTitle: String? = nil
    var dismiss: () -> Void
    var secondary: (() -> Void)? = nil
    var confirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CaptureThumbnail(urlString: thumbnailURL, fallbackIcon: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)

            if let secondaryTitle, let secondary {
                Button(secondaryTitle, action: secondary)
                    .buttonStyle(.bordered)
            }

            Button(confirmTitle, action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .glassPanel(cornerRadius: 16, material: .ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct CaptureThumbnail: View {
    var urlString: String?
    var fallbackIcon: String

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                if url.isFileURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 88, height: 54)
        .background(AppTheme.thumbnailFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: fallbackIcon)
            .font(.title3)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
