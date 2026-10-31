import Foundation

@main
struct AppStoreSmoke {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor
    static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }

    @MainActor
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PullrAppStoreSmoke-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PullrAppStoreSmoke.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let executable = root.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        case "$*" in
          *--dump-single-json*) echo '{"title":"Fixture","uploader":"Fixture"}'; exit 0 ;;
        esac
        i=1
        while [ "$i" -le 20 ]; do
          printf '[download] %s.0%% of 1.00MiB at 1.00MiB/s ETA 00:01\n' "$i"
          sleep 0.05
          i=$((i + 1))
        done
        echo '__PULLR_OUTPUT__:\(root.appendingPathComponent("fixture.mp4").path)'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.save(AppSettings(downloadFolder: root.path, ytDLPPath: executable.path, ffmpegPath: executable.path))
        let file = root.appendingPathComponent("queue.json")
        let queue = QueueStore(fileURL: file)
        let item = DownloadItem(url: "https://example.com/fixture.mp4", title: "Fixture", uploader: "Fixture", thumbnailURL: "https://example.com/poster.png", selectedPresetID: ExportPreset.Defaults.original)
        try queue.save([item])
        func makeStore() -> AppStore {
            AppStore(settingsStore: settingsStore,
                     presetStore: PresetStore(fileURL: root.appendingPathComponent("presets.json")),
                     historyStore: HistoryStore(fileURL: root.appendingPathComponent("history.json")),
                     listeningHistoryStore: ListeningHistoryStore(fileURL: root.appendingPathComponent("listening.jsonl")),
                     websiteActivityStore: WebsiteActivityStore(fileURL: root.appendingPathComponent("activity.jsonl")),
                     queueStore: queue,
                     seasonStore: SeasonStore(fileURL: root.appendingPathComponent("season.json")),
                     downloadLogStore: DownloadLogStore(directory: root.appendingPathComponent("logs")))
        }
        let store = makeStore()
        store.startQueue()
        var checkpoints = 0
        var lastWrite = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
            let current = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
            if current != lastWrite { checkpoints += 1; lastWrite = current }
            if store.items.first?.status == .completed { break }
        }
        try check(store.items.first?.status == .completed, "AppStore download did not complete")
        try check(checkpoints <= 6, "Transient download events rewrote queue \(checkpoints) times (budget 6)")
        try check(store.items[0].logs.filter { $0.hasPrefix("[download]") }.count == 20, "Progress logs lost")
        let persisted = try queue.load()
        try check(persisted.first?.status == .completed, "Completed status was not durable")
        let reloaded = makeStore()
        try check(reloaded.items.first?.id == item.id && reloaded.items.first?.status == .completed, "Restart lost queue")
        store.items[0].status = .cancelled
        store.retry(store.items[0])
        try await Task.sleep(nanoseconds: 80_000_000)
        store.cancel(store.items[0])
        store.retry(store.items[0])
        let retryDeadline = Date().addingTimeInterval(15)
        while store.items.first?.status != .completed && Date() < retryDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try check(store.items.first?.status == .completed && store.activeItemIDs.isEmpty, "Immediate cancel/retry was overwritten")
        var finished = DownloadItem(url: "https://example.com/finished.mp4", title: "Finished", selectedPresetID: ExportPreset.Defaults.original, status: .completed)
        try queue.save([finished])
        let dormant = makeStore()
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(!dormant.items[0].logs.contains("Fetching metadata..."), "Completed history launched an unnecessary metadata query on startup")
        finished.status = .waiting
        try queue.save([finished])
        let waiting = makeStore()
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(waiting.items[0].logs.contains("Fetching metadata..."), "Waiting download lost metadata prefetch")
        print("PASS: AppStore retained 20 logs with \(checkpoints) checkpoints; completion, restart, cancel/retry and no completed-history startup queries verified")
    }
}
