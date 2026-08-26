import AppKit
import Foundation
import OSLog

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedSection: AppSection = .downloads
    @Published var queueViewMode: QueueViewMode = .grid
    @Published var items: [DownloadItem] = []
    @Published var presets: [ExportPreset] = []
    @Published var settings: AppSettings
    @Published var history: [HistoryItem] = []
    @Published var listeningHistory: [ListeningEvent] = []
    @Published var websiteActivity: [WebsiteActivityEvent] = []
    @Published var dependencyReport: DependencyReport
    @Published var toast: ToastMessage?
    @Published var isQueueRunning = false
    @Published var activeItemIDs: Set<UUID> = []
    @Published var isUpdatingYTDLP = false
    @Published var lastYTDLPUpdateOutput: String?
    @Published var expandingPlaylistIDs: Set<UUID> = []
    @Published var clipboardSuggestion: ClipboardSuggestion?
    @Published var browserCaptureSuggestion: BrowserCaptureSuggestion?
    @Published var browserCaptureProbe: BrowserCaptureProbeState = .idle
    @Published var seasonPlan: SeasonCapturePlan?
    @Published var isSeasonManagerPresented = false

    private let clipboardReader = ClipboardReader()
    private let queueManager = DownloadQueueManager()
    private let binaryUpdateService = BinaryUpdateService()
    private let metadataService = MetadataService()
    private let settingsStore: SettingsStore
    private let presetStore: PresetStore
    private let historyStore: HistoryStore
    private let listeningHistoryStore: ListeningHistoryStore
    private let websiteActivityStore: WebsiteActivityStore
    private let queueStore: QueueStore
    private let seasonStore: SeasonStore
    private let downloadLogStore: DownloadLogStore
    private let logger = Logger(subsystem: "app.pullr.Pullr", category: "Downloads")
    private var metadataFetchIDs: Set<UUID> = []
    private var transient403RetryItemIDs: Set<UUID> = []
    private var lastClipboardChangeCount = -1

    init(
        settingsStore: SettingsStore = SettingsStore(),
        presetStore: PresetStore = PresetStore(),
        historyStore: HistoryStore = HistoryStore(),
        listeningHistoryStore: ListeningHistoryStore = ListeningHistoryStore(),
        websiteActivityStore: WebsiteActivityStore = WebsiteActivityStore(),
        queueStore: QueueStore = QueueStore(),
        seasonStore: SeasonStore = SeasonStore(),
        downloadLogStore: DownloadLogStore = DownloadLogStore()
    ) {
        self.settingsStore = settingsStore
        self.presetStore = presetStore
        self.historyStore = historyStore
        self.listeningHistoryStore = listeningHistoryStore
        self.websiteActivityStore = websiteActivityStore
        self.queueStore = queueStore
        self.seasonStore = seasonStore
        self.downloadLogStore = downloadLogStore
        let loadedSettings = settingsStore.load()
        self.settings = loadedSettings
        self.presets = presetStore.load()
        self.history = historyStore.load()
        self.listeningHistory = listeningHistoryStore.load()
        self.websiteActivity = websiteActivityStore.load()
        let loadedItems = queueStore.load()
        let normalizedItems = loadedItems.map { item in
            guard item.selectedPresetID == ExportPreset.Defaults.bestYouTubeAudio else { return item }
            var normalized = item
            normalized.url = URLExtractor.singleYouTubeVideoURL(item.url)
            normalized.isPlaylist = false
            return normalized
        }
        self.items = normalizedItems
        if zip(loadedItems, normalizedItems).contains(where: { $0.url != $1.url || $0.isPlaylist != $1.isPlaylist }) {
            queueStore.save(normalizedItems)
        }
        self.seasonPlan = seasonStore.load()
        self.dependencyReport = DependencyChecker.check(settings: loadedSettings)

        Task { @MainActor in
            prefetchMissingMetadata()
        }

        if loadedSettings.autoUpdateYTDLPOnLaunch {
            Task { @MainActor in
                updateYTDLP(isAutomatic: true)
            }
        }
    }

    var visiblePresets: [ExportPreset] {
        presets.filter(\.isVisibleInDropdown)
    }

    func refreshListeningHistory() {
        listeningHistory = listeningHistoryStore.load()
        websiteActivity = websiteActivityStore.load()
    }

    func clearListeningHistory() {
        listeningHistoryStore.clear()
        websiteActivityStore.clear()
        listeningHistory = []
        websiteActivity = []
        showToast("Activity history cleared.", kind: .info)
    }

    var queueSummary: String {
        let waiting = items.filter { $0.status == .waiting }.count
        let active = items.filter { [.fetchingInfo, .downloading, .paused, .converting].contains($0.status) }.count
        let completed = items.filter { $0.status == .completed }.count
        return "\(waiting) waiting  \(active)/\(maxConcurrentDownloads) active  \(completed) done"
    }

    var maxConcurrentDownloads: Int {
        min(max(settings.maxConcurrentDownloads, 1), 6)
    }

    func refreshDependencies() {
        dependencyReport = DependencyChecker.check(settings: settings)
    }

    func saveSettings() {
        settingsStore.save(settings)
        refreshDependencies()
    }

    func setMaxConcurrentDownloads(_ value: Int) {
        settings.maxConcurrentDownloads = min(max(value, 1), 6)
        saveSettings()
    }

    func resetSettings() {
        settings = settingsStore.reset()
        refreshDependencies()
        showToast("Settings reset.", kind: .info)
    }

    func savePresets() {
        presetStore.save(presets)
    }

    func resetDefaultPresets() {
        presets = presetStore.resetDefaults()
        showToast("Default presets restored.", kind: .success)
    }

    func addPreset() {
        let baseID = visiblePresets.first?.id ?? ExportPreset.Defaults.bestMP4
        presets.append(
            ExportPreset(
                name: "New Preset",
                kind: .video,
                selectedFrom: preset(id: baseID)
            )
        )
        savePresets()
    }

    func duplicatePreset(_ preset: ExportPreset) {
        var duplicate = preset
        duplicate.id = UUID()
        duplicate.name = "\(preset.name) Copy"
        duplicate.isDefault = false
        presets.append(duplicate)
        savePresets()
    }

    func deletePreset(id: UUID) {
        guard let preset = preset(id: id), !preset.isDefault else {
            showToast("Default presets cannot be deleted. Duplicate one first.", kind: .warning)
            return
        }
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func movePreset(id: UUID, direction: Int) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard presets.indices.contains(destination) else { return }
        presets.swapAt(index, destination)
        savePresets()
    }

    func updatePreset(_ preset: ExportPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        savePresets()
    }

    func preset(id: UUID) -> ExportPreset? {
        presets.first { $0.id == id }
    }

    func addFromClipboard() {
        guard let string = clipboardReader.readString(), !string.isEmpty else {
            showToast("Clipboard does not contain a supported link.", kind: .warning)
            return
        }
        addURLs(from: string, source: "clipboard")
    }

    func monitorClipboard() async {
        checkClipboardForSuggestion()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            checkClipboardForSuggestion()
        }
    }

    func acceptClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion else { return }
        clipboardSuggestion = nil
        selectedSection = .downloads
        addURLs(from: suggestion.url, source: "clipboard suggestion")
    }

    func dismissClipboardSuggestion() {
        clipboardSuggestion = nil
    }

    func acceptBrowserCapture() {
        guard let suggestion = browserCaptureSuggestion else { return }
        let probedMetadata: DownloadMetadata? = if case .loaded(let metadata) = browserCaptureProbe { metadata } else { nil }
        browserCaptureSuggestion = nil
        browserCaptureProbe = .idle
        selectedSection = .downloads
        let episodeIndex = seasonPlan?.episodes.firstIndex { episode in
            normalizedPageURL(episode.pageURL) == normalizedPageURL(suggestion.referrerURL ?? "")
        }
        let presetID = episodeIndex == nil ? nil : seasonPlan?.quality.presetID
        let itemIDs = addURLs(
            from: suggestion.url,
            source: "browser capture",
            referrerURL: suggestion.referrerURL,
            userAgent: suggestion.userAgent,
            originURL: suggestion.originURL,
            selectedPresetID: presetID,
            prefetchedMetadata: probedMetadata,
            fallbackThumbnailURL: suggestion.thumbnailURL
        )
        if let episodeIndex, let itemID = itemIDs.first {
            seasonPlan?.episodes[episodeIndex].capturedURL = suggestion.url
            seasonPlan?.episodes[episodeIndex].downloadItemID = itemID
            persistSeason()
        }
    }

    func dismissBrowserCapture() {
        browserCaptureSuggestion = nil
        browserCaptureProbe = .idle
    }

    var browserCaptureProbeSummary: String {
        switch browserCaptureProbe {
        case .idle:
            return "Ready to review"
        case .loading:
            return "Checking duration, resolution, and size…"
        case .failed:
            return "Details unavailable · download is still allowed"
        case .loaded(let metadata):
            var parts: [String] = []
            if let height = metadata.height { parts.append("\(height)p") }
            if let duration = metadata.duration {
                let seconds = max(0, Int(duration.rounded()))
                parts.append(seconds >= 3600
                    ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
                    : String(format: "%d:%02d", seconds / 60, seconds % 60))
            }
            let size = metadata.estimatedFileSize ?? browserCaptureSuggestion?.contentLength
            if let size, size > 0 {
                parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let format = metadata.formatDescription, !format.isEmpty { parts.append(format) }
            if metadata.isLive { parts.append("Live") }
            if metadata.hasDRM { parts.append("DRM detected") }
            return parts.isEmpty ? "Stream details loaded" : parts.joined(separator: " · ")
        }
    }

    var browserCaptureThumbnailURL: String? {
        if case .loaded(let metadata) = browserCaptureProbe, let thumbnailURL = metadata.thumbnailURL {
            return thumbnailURL
        }
        return browserCaptureSuggestion?.thumbnailURL
    }

    func beginSeasonCapture() {
        guard
            let referrer = browserCaptureSuggestion?.referrerURL,
            let proposedPlan = SeasonCapturePlan(referrerURL: referrer)
        else {
            showToast("This page does not expose a recognizable episode number.", kind: .warning)
            return
        }

        if seasonPlan?.urlPrefix != proposedPlan.urlPrefix {
            seasonPlan = proposedPlan
            persistSeason()
        }
        isSeasonManagerPresented = true
    }

    func presentSeasonManager() {
        guard seasonPlan != nil else {
            showToast("Capture one episode first, then choose Plan season.", kind: .info)
            return
        }
        isSeasonManagerPresented = true
    }

    func updateSeasonRange(first: Int, last: Int) {
        seasonPlan?.setRange(first: first, last: last)
        persistSeason()
    }

    func setSeasonQuality(_ quality: SeasonQuality) {
        seasonPlan?.quality = quality
        let waitingItemIDs = Set(seasonPlan?.episodes.compactMap(\.downloadItemID) ?? [])
        for index in items.indices where waitingItemIDs.contains(items[index].id) && items[index].status == .waiting {
            items[index].selectedPresetID = quality.presetID
        }
        persistQueue()
        persistSeason()
    }

    func toggleSeasonEpisode(_ episodeID: UUID) {
        guard let index = seasonPlan?.episodes.firstIndex(where: { $0.id == episodeID }) else { return }
        seasonPlan?.episodes[index].isSelected.toggle()
        persistSeason()
    }

    func openSeasonEpisode(_ episode: SeasonEpisode) {
        guard let url = URL(string: episode.pageURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func openNextSeasonEpisode() {
        guard let episode = seasonPlan?.episodes.first(where: { $0.isSelected && $0.capturedURL == nil }) else {
            showToast("Every selected episode has a captured stream.", kind: .success)
            return
        }
        openSeasonEpisode(episode)
    }

    func clearSeasonPlan() {
        seasonPlan = nil
        isSeasonManagerPresented = false
        persistSeason()
    }

    private func checkClipboardForSuggestion() {
        let changeCount = clipboardReader.changeCount
        guard changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = changeCount

        guard let string = clipboardReader.readString() else {
            clipboardSuggestion = nil
            return
        }

        let extracted = URLExtractor.extract(from: string).urls
        guard let candidate = extracted.first(where: { URLExtractor.isLikelyMediaURL($0.normalizedURL) }),
              !items.contains(where: { $0.url == candidate.normalizedURL })
        else {
            clipboardSuggestion = nil
            return
        }

        clipboardSuggestion = ClipboardSuggestion(url: candidate.normalizedURL)
    }

    func addFromDeepLink(_ url: URL) {
        guard url.scheme == "pullr", url.host == "add" else { return }
        if let request = BrowserPresetRequest(deepLink: url), preset(id: request.presetID) != nil {
            selectedSection = .downloads
            let itemIDs = addURLs(from: request.url, source: "browser extension", selectedPresetID: request.presetID)
            if request.startImmediately, !itemIDs.isEmpty {
                startQueue()
            }
            return
        }

        guard let suggestion = BrowserCaptureSuggestion(deepLink: url) else {
            showToast("No media stream was detected. Start playback, then reopen the extension.", kind: .warning)
            return
        }

        selectedSection = .downloads
        browserCaptureSuggestion = suggestion
        probeBrowserCapture(suggestion)
    }

    @discardableResult
    func addURLs(
        from text: String,
        source: String = "paste",
        referrerURL: String? = nil,
        userAgent: String? = nil,
        originURL: String? = nil,
        selectedPresetID: UUID? = nil,
        prefetchedMetadata: DownloadMetadata? = nil,
        fallbackThumbnailURL: String? = nil
    ) -> [UUID] {
        let existing = settings.duplicateHandling == .ignore ? Set(items.map(\.url)) : []
        let result = URLExtractor.extract(from: text, existingURLs: existing)

        guard !result.urls.isEmpty else {
            let duplicateHint = result.duplicates.isEmpty ? "" : " Duplicates were ignored."
            showToast("No supported HTTP or HTTPS links found.\(duplicateHint)", kind: .warning)
            return []
        }

        let presetID = selectedPresetID ?? visiblePresets.first?.id ?? ExportPreset.Defaults.bestMP4
        let newItems = result.urls.map { extracted in
            DownloadItem(
                url: extracted.normalizedURL,
                title: prefetchedMetadata?.title ?? (extracted.isPlaylist ? "Playlist" : nil),
                uploader: prefetchedMetadata?.uploader,
                thumbnailURL: prefetchedMetadata?.thumbnailURL ?? fallbackThumbnailURL,
                selectedPresetID: presetID,
                isPlaylist: prefetchedMetadata?.isPlaylist == true || extracted.isPlaylist,
                playlistEntryCount: prefetchedMetadata?.playlistEntryCount,
                referrerURL: referrerURL,
                userAgent: userAgent,
                originURL: originURL
            )
        }

        items.insert(contentsOf: newItems, at: 0)
        if let suggestion = clipboardSuggestion,
           newItems.contains(where: { $0.url == suggestion.url }) {
            clipboardSuggestion = nil
        }
        persistQueue()
        if prefetchedMetadata == nil {
            for item in newItems {
                prefetchMetadata(for: item.id)
            }
        }

        let duplicateSuffix = result.duplicates.isEmpty ? "" : " \(result.duplicates.count) duplicate ignored."
        showToast("Added \(newItems.count) link\(newItems.count == 1 ? "" : "s") from \(source).\(duplicateSuffix)", kind: .success)
        return newItems.map(\.id)
    }

    func setPreset(_ presetID: UUID, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].selectedPresetID = presetID
        persistQueue()
    }

    func startQueue() {
        refreshDependencies()

        guard dependencyReport.isReady, let ytDLPPath = dependencyReport.ytDLP.resolvedPath else {
            selectedSection = .settings
            showToast("yt-dlp or ffmpeg could not be found. Check Dependencies in Settings.", kind: .error)
            return
        }

        if isQueueRunning {
            stopQueue()
            return
        }

        let failedIDs = items.filter { $0.status == .failed }.map(\.id)
        for itemID in failedIDs {
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            transient403RetryItemIDs.remove(itemID)
            items[index].prepareForRetry()
            appendLog("Retry queued.", to: itemID)
        }
        if !failedIDs.isEmpty {
            persistQueue()
        }

        guard items.contains(where: { $0.status == .waiting }) else {
            showToast("There are no waiting downloads.", kind: .info)
            return
        }

        isQueueRunning = true
        processAvailableSlots(ytDLPPath: ytDLPPath)
    }

    func stopQueue() {
        isQueueRunning = false
        let activeIDs = activeItemIDs
        queueManager.cancelAllDownloads()
        for itemID in activeIDs {
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].status = .cancelled
                items[index].speed = nil
                items[index].eta = nil
                items[index].errorMessage = "Cancelled by user."
                appendLog("Cancelled by user.", to: itemID)
                logger.info("Download cancelled id=\(itemID.uuidString, privacy: .public)")
            }
        }
        activeItemIDs = []
        persistQueue()
        showToast("Queue stopped.", kind: .info)
    }

    func cancel(_ item: DownloadItem) {
        if activeItemIDs.contains(item.id) {
            queueManager.cancelDownload(itemID: item.id)
            activeItemIDs.remove(item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].status = .cancelled
                items[index].speed = nil
                items[index].eta = nil
                items[index].errorMessage = "Cancelled by user."
                appendLog("Cancelled by user.", to: item.id)
                logger.info("Download cancelled id=\(item.id.uuidString, privacy: .public)")
            }
            persistQueue()
            processQueueAfterCancellation()
        } else if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = .cancelled
            items[index].speed = nil
            items[index].eta = nil
            items[index].errorMessage = "Cancelled by user."
            appendLog("Cancelled by user.", to: item.id)
            logger.info("Download cancelled id=\(item.id.uuidString, privacy: .public)")
            persistQueue()
        }
    }

    func pause(_ item: DownloadItem) {
        guard activeItemIDs.contains(item.id) else {
            showToast("Only active downloads can be paused.", kind: .warning)
            return
        }

        guard queueManager.pauseDownload(itemID: item.id) else {
            showToast("Could not pause this download.", kind: .error)
            return
        }

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = .paused
            items[index].speed = nil
            items[index].eta = nil
            appendLog("Paused.", to: item.id)
            persistQueue()
        }
    }

    func resume(_ item: DownloadItem) {
        guard activeItemIDs.contains(item.id) else {
            showToast("Only paused active downloads can be resumed.", kind: .warning)
            return
        }

        guard queueManager.resumeDownload(itemID: item.id) else {
            showToast("Could not resume this download.", kind: .error)
            return
        }

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = items[index].progress > 0 ? .downloading : .fetchingInfo
            appendLog("Resumed.", to: item.id)
            persistQueue()
        }
    }

    func retry(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              items[index].status == .failed || items[index].status == .cancelled
        else { return }

        transient403RetryItemIDs.remove(item.id)
        items[index].prepareForRetry()
        appendLog("Retry queued.", to: item.id)
        logger.info("Download retry queued id=\(item.id.uuidString, privacy: .public)")
        persistQueue()

        if isQueueRunning {
            refreshDependencies()
            if let ytDLPPath = dependencyReport.ytDLP.resolvedPath {
                processAvailableSlots(ytDLPPath: ytDLPPath)
            }
        } else {
            startQueue()
        }
    }

    func remove(_ item: DownloadItem) {
        if activeItemIDs.contains(item.id) {
            cancel(item)
        }
        guard let item = items.first(where: { $0.id == item.id }) else { return }
        do {
            try downloadLogStore.archive(item)
        } catch {
            showToast("Could not archive this download’s logs, so it was not removed.", kind: .error)
            return
        }
        items.removeAll { $0.id == item.id }
        persistQueue()
    }

    func clearCompleted() {
        do {
            try items.filter { $0.status == .completed }.forEach(downloadLogStore.archive)
        } catch {
            showToast("Could not archive every completed download log, so nothing was cleared.", kind: .error)
            return
        }
        items.removeAll { $0.status == .completed }
        persistQueue()
    }

    func redownload(_ historyItem: HistoryItem) {
        let presetID = visiblePresets.first?.id ?? ExportPreset.Defaults.bestMP4
        items.append(
            DownloadItem(
                url: historyItem.url,
                title: historyItem.title,
                selectedPresetID: presetID,
                isPlaylist: URLExtractor.extract(from: historyItem.url).urls.first?.isPlaylist ?? false
            )
        )
        selectedSection = .downloads
        persistQueue()
        if let item = items.last {
            prefetchMetadata(for: item.id)
        }
    }

    func removeHistory(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        historyStore.save(history)
    }

    func clearHistory() {
        do {
            try historyStore.clear()
            history.removeAll()
            showToast("Download history cleared. Files were not deleted.", kind: .info)
        } catch {
            showToast("Download history could not be cleared: \(error.localizedDescription)", kind: .error)
        }
    }

    func openInFinder(path: String?) {
        guard let path, !path.isEmpty else {
            showToast("No output file path is available yet.", kind: .warning)
            return
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDiagnosticLog(for item: DownloadItem) {
        let url = downloadLogStore.logURL(for: item.id)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                for line in item.logs {
                    try downloadLogStore.append(line, for: item.id)
                }
            } catch {
                showToast("Could not create the diagnostic log.", kind: .error)
                logger.error("Could not create diagnostic log id=\(item.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDiagnosticsFolder() {
        do {
            try FileManager.default.createDirectory(at: downloadLogStore.diagnosticsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(downloadLogStore.diagnosticsDirectory)
        } catch {
            showToast("Could not open the diagnostics folder.", kind: .error)
            logger.error("Could not open diagnostics folder error=\(error.localizedDescription, privacy: .private)")
        }
    }

    func importHistoryItemToMusic(_ item: HistoryItem) {
        guard let path = item.outputPath else {
            showToast("No output file path is available yet.", kind: .warning)
            return
        }
        do {
            try MusicLibraryService.importFile(at: path)
            showToast("Imported \(item.title) into Music.", kind: .success)
        } catch {
            showToast(error.localizedDescription, kind: .error)
        }
    }

    func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolder = url.path
            saveSettings()
        }
    }

    func chooseBinaryPath(for binary: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if binary == "yt-dlp" {
                settings.ytDLPPath = url.path
            } else {
                settings.ffmpegPath = url.path
            }
            saveSettings()
        }
    }

    func updateYTDLP(isAutomatic: Bool = false) {
        refreshDependencies()

        guard let ytDLPPath = dependencyReport.ytDLP.resolvedPath else {
            if !isAutomatic {
                showToast("yt-dlp was not found. Choose a binary path in Settings.", kind: .error)
            }
            return
        }

        guard !isUpdatingYTDLP else {
            if !isAutomatic {
                showToast("yt-dlp update is already running.", kind: .info)
            }
            return
        }

        isUpdatingYTDLP = true
        lastYTDLPUpdateOutput = nil
        if !isAutomatic {
            showToast("Updating yt-dlp...", kind: .info)
        }

        binaryUpdateService.updateYTDLP(ytDLPPath: ytDLPPath) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isUpdatingYTDLP = false
                self.refreshDependencies()

                switch result {
                case .success(let updateResult) where updateResult.exitCode == 0:
                    self.lastYTDLPUpdateOutput = updateResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isAutomatic {
                        self.showToast("yt-dlp update finished.", kind: .success)
                    }
                case .success(let updateResult):
                    self.lastYTDLPUpdateOutput = updateResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isAutomatic {
                        self.showToast("yt-dlp update failed with exit code \(updateResult.exitCode).", kind: .error)
                    }
                case .failure(let error):
                    self.lastYTDLPUpdateOutput = error.localizedDescription
                    if !isAutomatic {
                        self.showToast(error.localizedDescription, kind: .error)
                    }
                }
            }
        }
    }

    func showToast(_ message: String, kind: ToastMessage.Kind = .info) {
        let nextToast = ToastMessage(message: message, kind: kind)
        toast = nextToast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard self?.toast == nextToast else { return }
            self?.toast = nil
        }
    }

    func refreshMetadata(for item: DownloadItem) {
        prefetchMetadata(for: item.id, force: true)
    }

    func expandPlaylist(_ item: DownloadItem) {
        guard item.isPlaylist else {
            showToast("This item is not a playlist.", kind: .warning)
            return
        }

        guard !activeItemIDs.contains(item.id) else {
            showToast("Stop this playlist before expanding it.", kind: .warning)
            return
        }

        refreshDependencies()
        guard let ytDLPPath = dependencyReport.ytDLP.resolvedPath else {
            selectedSection = .settings
            showToast("yt-dlp was not found. Check Dependencies in Settings.", kind: .error)
            return
        }

        guard !expandingPlaylistIDs.contains(item.id) else {
            showToast("Playlist expansion is already running.", kind: .info)
            return
        }

        expandingPlaylistIDs.insert(item.id)
        showToast("Expanding playlist...", kind: .info)

        metadataService.fetchPlaylistEntries(
            ytDLPPath: ytDLPPath,
            url: item.url,
            referrerURL: item.referrerURL
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.expandingPlaylistIDs.remove(item.id)

                switch result {
                case .success(let entries):
                    self.replacePlaylist(item, with: entries)
                case .failure(let error):
                    if self.items.contains(where: { $0.id == item.id }) {
                        self.appendLog("Playlist expansion failed: \(error.localizedDescription)", to: item.id)
                        self.persistQueue()
                    }
                    self.showToast("Playlist expansion failed. Open logs for details.", kind: .error)
                }
            }
        }
    }

    private func persistQueue() {
        queueStore.save(items)
    }

    private func appendLog(_ line: String, to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].appendLog(line)
        do {
            try downloadLogStore.append(line, for: itemID)
        } catch {
            logger.error("Could not persist download log id=\(itemID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
        }
    }

    private func persistSeason() {
        seasonStore.save(seasonPlan)
    }

    private func normalizedPageURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func probeBrowserCapture(_ suggestion: BrowserCaptureSuggestion) {
        refreshDependencies()
        guard let ytDLPPath = dependencyReport.ytDLP.resolvedPath else {
            browserCaptureProbe = .failed("yt-dlp is unavailable")
            return
        }

        browserCaptureProbe = .loading
        let captureID = suggestion.id
        metadataService.fetchMetadata(
            ytDLPPath: ytDLPPath,
            url: suggestion.url,
            referrerURL: suggestion.referrerURL,
            userAgent: suggestion.userAgent,
            originURL: suggestion.originURL
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.browserCaptureSuggestion?.id == captureID else { return }
                switch result {
                case .success(let metadata): self.browserCaptureProbe = .loaded(metadata)
                case .failure(let error): self.browserCaptureProbe = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func applyMetadata(_ metadata: DownloadMetadata, to itemID: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[itemIndex].title = metadata.title ?? items[itemIndex].title
        items[itemIndex].uploader = metadata.uploader ?? items[itemIndex].uploader
        items[itemIndex].thumbnailURL = metadata.thumbnailURL ?? items[itemIndex].thumbnailURL
        items[itemIndex].isPlaylist = metadata.isPlaylist || items[itemIndex].isPlaylist
        items[itemIndex].playlistEntryCount = metadata.playlistEntryCount
        appendLog("Metadata loaded.", to: itemID)
        persistQueue()
    }

    private func replacePlaylist(_ item: DownloadItem, with entries: [PlaylistEntryMetadata]) {
        guard let playlistIndex = items.firstIndex(where: { $0.id == item.id }) else { return }

        let rangedEntries = applyPlaylistDefaults(to: entries)
        let existingURLs = settings.duplicateHandling == .ignore
            ? Set(items.map(\.url).filter { $0 != item.url })
            : Set<String>()

        var seenURLs = existingURLs
        let uniqueEntries = rangedEntries.filter { entry in
            guard settings.duplicateHandling == .ignore else { return true }
            guard !seenURLs.contains(entry.url) else { return false }
            seenURLs.insert(entry.url)
            return true
        }

        guard !uniqueEntries.isEmpty else {
            appendLog("Playlist expansion found no new videos.", to: item.id)
            persistQueue()
            showToast("No new videos found in playlist.", kind: .warning)
            return
        }

        let expandedItems = uniqueEntries.map { entry in
            DownloadItem(
                url: entry.url,
                title: entry.title,
                uploader: entry.uploader ?? item.uploader,
                thumbnailURL: entry.thumbnailURL,
                selectedPresetID: item.selectedPresetID,
                status: .waiting,
                isPlaylist: false,
                sourcePlaylistTitle: item.displayTitle,
                playlistIndex: entry.playlistIndex,
                referrerURL: item.referrerURL,
                userAgent: item.userAgent,
                originURL: item.originURL,
                logs: ["Expanded from playlist: \(item.displayTitle)"]
            )
        }

        items.remove(at: playlistIndex)
        items.insert(contentsOf: expandedItems, at: playlistIndex)
        persistQueue()
        showToast("Expanded playlist into \(expandedItems.count) video\(expandedItems.count == 1 ? "" : "s").", kind: .success)
    }

    private func applyPlaylistDefaults(to entries: [PlaylistEntryMetadata]) -> [PlaylistEntryMetadata] {
        var result = entries

        if let start = settings.playlistDefaults.rangeStart, start > 1 {
            result = Array(result.dropFirst(start - 1))
        }

        if let end = settings.playlistDefaults.rangeEnd, end > 0 {
            let start = max(settings.playlistDefaults.rangeStart ?? 1, 1)
            let count = max(0, end - start + 1)
            result = Array(result.prefix(count))
        }

        if settings.playlistDefaults.reverseOrder {
            result.reverse()
        }

        return result
    }

    private func prefetchMissingMetadata() {
        for item in items where item.title == nil || item.thumbnailURL == nil || item.uploader == nil {
            prefetchMetadata(for: item.id)
        }
    }

    private func prefetchMetadata(for itemID: UUID, force: Bool = false) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = items[index]

        if !force, item.title != nil, item.uploader != nil, item.thumbnailURL != nil {
            return
        }

        refreshDependencies()
        guard let ytDLPPath = dependencyReport.ytDLP.resolvedPath else { return }
        guard !metadataFetchIDs.contains(itemID) else { return }

        metadataFetchIDs.insert(itemID)
        appendLog("Fetching metadata...", to: itemID)
        persistQueue()

        metadataService.fetchMetadata(
            ytDLPPath: ytDLPPath,
            url: item.url,
            referrerURL: item.referrerURL,
            userAgent: item.userAgent,
            originURL: item.originURL
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.metadataFetchIDs.remove(itemID)
                guard self.items.contains(where: { $0.id == itemID }) else { return }

                switch result {
                case .success(let metadata):
                    self.applyMetadata(metadata, to: itemID)
                case .failure(let error):
                    self.appendLog("Metadata fetch failed: \(error.localizedDescription)", to: itemID)
                }

                self.persistQueue()
            }
        }
    }

    private func processAvailableSlots(ytDLPPath: String) {
        guard isQueueRunning else { return }

        activeItemIDs = queueManager.activeItemIDs()

        while activeItemIDs.count < maxConcurrentDownloads,
              let index = items.firstIndex(where: { $0.status == .waiting }) {
            startItem(at: index, ytDLPPath: ytDLPPath)
            activeItemIDs = queueManager.activeItemIDs()
        }

        if activeItemIDs.isEmpty && !items.contains(where: { $0.status == .waiting }) {
            isQueueRunning = false
            showToast("Queue complete.", kind: .success)
        }
    }

    private func startItem(at index: Int, ytDLPPath: String) {
        let item = items[index]
        let preset = preset(id: item.selectedPresetID) ?? visiblePresets.first ?? ExportPreset.defaultPresets[0]
        let request = DownloadCommandRequest(
            url: item.url,
            preset: preset,
            outputFolder: settings.downloadFolder,
            namingTemplate: settings.namingTemplate,
            playlistOptions: settings.playlistDefaults,
            ffmpegPath: dependencyReport.ffmpeg.resolvedPath,
            playlistFolderName: settings.playlistDefaults.createPlaylistFolder ? item.sourcePlaylistTitle : nil,
            playlistIndex: item.playlistIndex,
            advancedArguments: settings.globalCustomArguments,
            referrerURL: item.referrerURL,
            concurrentFragments: settings.maxConcurrentFragments,
            userAgent: item.userAgent,
            originURL: item.originURL,
            outputDiscriminator: item.referrerURL == nil ? nil : String(item.id.uuidString.prefix(8))
        )

        do {
            let arguments = try CommandBuilder.buildArguments(for: request)
            items[index].status = .fetchingInfo
            items[index].errorMessage = nil
            appendLog("Starting download with preset: \(preset.name).", to: item.id)
            logger.info("Download started id=\(item.id.uuidString, privacy: .public)")
            persistQueue()

            queueManager.startDownload(
                itemID: item.id,
                ytDLPPath: ytDLPPath,
                arguments: arguments,
                eventHandler: { [weak self] event in
                    Task { @MainActor in
                        self?.handle(event, for: item.id)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(result, for: item.id, preset: preset, ytDLPPath: ytDLPPath)
                    }
                }
            )
        } catch {
            items[index].status = .failed
            items[index].errorMessage = error.localizedDescription
            appendLog("Could not start download: \(error.localizedDescription)", to: item.id)
            logger.error("Download start failed id=\(item.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            persistQueue()
        }
    }

    private func processQueueAfterCancellation() {
        guard isQueueRunning else { return }
        refreshDependencies()
        guard let ytDLPPath = dependencyReport.ytDLP.resolvedPath else { return }
        processAvailableSlots(ytDLPPath: ytDLPPath)
    }

    private func handle(_ event: YTDLPEvent, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }

        switch event {
        case .log(let line):
            appendLog(line, to: itemID)
        case .progress(let snapshot):
            items[index].progress = snapshot.progress
            items[index].speed = snapshot.speed
            items[index].eta = snapshot.eta
        case .status(let status):
            if !items[index].status.isTerminal && items[index].status != .paused {
                items[index].status = status
            }
        case .outputPath(let path):
            items[index].outputPath = path
        case .error(let message):
            items[index].errorMessage = message
        }

        persistQueue()
    }

    private func handleCompletion(
        _ result: Result<YTDLPResult, Error>,
        for itemID: UUID,
        preset: ExportPreset,
        ytDLPPath: String
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            activeItemIDs.remove(itemID)
            processAvailableSlots(ytDLPPath: ytDLPPath)
            return
        }

        switch result {
        case .success(let ytdlpResult) where ytdlpResult.exitCode == 0:
            transient403RetryItemIDs.remove(itemID)
            items[index].status = .completed
            items[index].progress = 1
            items[index].speed = nil
            items[index].eta = nil
            items[index].errorMessage = nil
            items[index].completedAt = Date()
            appendLog("Download completed.", to: itemID)
            logger.info("Download completed id=\(itemID.uuidString, privacy: .public)")
            history.insert(
                HistoryItem(
                    title: items[index].displayTitle,
                    url: items[index].url,
                    presetName: preset.name,
                    completedAt: Date(),
                    outputPath: items[index].outputPath
                ),
                at: 0
            )
            historyStore.save(history)
            if preset.id == ExportPreset.Defaults.bestYouTubeAudio,
               let outputPath = items[index].outputPath {
                do {
                    try MusicLibraryService.importFile(at: outputPath)
                    appendLog("Imported into Music.", to: itemID)
                    logger.info("Music import completed id=\(itemID.uuidString, privacy: .public)")
                    showToast("Downloaded and imported \(items[index].displayTitle) into Music.", kind: .success)
                } catch {
                    appendLog("Music import failed: \(error.localizedDescription)", to: itemID)
                    logger.error("Music import failed id=\(itemID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
                    showToast("Download finished, but Music import needs attention.", kind: .warning)
                }
            }
        case .success(let ytdlpResult):
            if YTDLPService.shouldRetryTransient403(
                url: items[index].url,
                logs: items[index].logs,
                alreadyRetried: transient403RetryItemIDs.contains(itemID)
            ) {
                transient403RetryItemIDs.insert(itemID)
                items[index].status = .waiting
                items[index].progress = 0
                items[index].speed = nil
                items[index].eta = nil
                items[index].errorMessage = nil
                appendLog("YouTube returned a temporary 403. Retrying once...", to: itemID)
                logger.notice("Transient YouTube 403; retrying id=\(itemID.uuidString, privacy: .public)")
            } else {
                transient403RetryItemIDs.remove(itemID)
                items[index].status = .failed
                items[index].speed = nil
                items[index].eta = nil
                items[index].errorMessage = "yt-dlp exited with code \(ytdlpResult.exitCode). Open logs for details."
                appendLog("yt-dlp exited with code \(ytdlpResult.exitCode).", to: itemID)
                logger.error("yt-dlp failed id=\(itemID.uuidString, privacy: .public) exitCode=\(ytdlpResult.exitCode, privacy: .public)")
            }
        case .failure(let error as YTDLPServiceError) where error.localizedDescription == YTDLPServiceError.cancelled.localizedDescription:
            transient403RetryItemIDs.remove(itemID)
            items[index].status = .cancelled
            items[index].speed = nil
            items[index].eta = nil
            items[index].errorMessage = "Cancelled by user."
            appendLog("Cancelled by user.", to: itemID)
            logger.info("Download cancelled id=\(itemID.uuidString, privacy: .public)")
        case .failure(let error):
            transient403RetryItemIDs.remove(itemID)
            items[index].status = .failed
            items[index].speed = nil
            items[index].eta = nil
            items[index].errorMessage = error.localizedDescription
            appendLog("Download failed: \(error.localizedDescription)", to: itemID)
            logger.error("Download failed id=\(itemID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
        }

        activeItemIDs.remove(itemID)
        persistQueue()
        processAvailableSlots(ytDLPPath: ytDLPPath)
    }
}

private extension ExportPreset {
    init(name: String, kind: PresetKind, selectedFrom preset: ExportPreset?) {
        self.init(
            name: name,
            kind: kind,
            formatSelector: preset?.formatSelector,
            maxHeight: preset?.maxHeight,
            audioFormat: preset?.audioFormat,
            audioQuality: preset?.audioQuality,
            mergeOutputFormat: preset?.mergeOutputFormat,
            customArguments: preset?.customArguments ?? []
        )
    }
}
