import Foundation

struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(description: "\(message). Expected \(expected), got \(actual)")
    }
}

func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw TestFailure(description: message)
    }
    return value
}

let tests: [(String, () throws -> Void)] = [
    ("URLExtractor extracts supported links", {
        let result = URLExtractor.extract(from: "Watch https://www.youtube.com/watch?v=abc123 and youtu.be/xyz789")
        try expectEqual(result.urls.map(\.normalizedURL), [
            "https://www.youtube.com/watch?v=abc123",
            "https://youtu.be/xyz789"
        ], "Supported links should normalize")
        try expect(result.duplicates.isEmpty, "No duplicates expected")
    }),
    ("URLExtractor accepts web and M3U8 links", {
        let result = URLExtractor.extract(from: "https://vimeo.com/123 https://media.example.com/master.m3u8?token=abc")
        try expectEqual(result.urls.count, 2, "HTTP links should be accepted")
        try expect(URLExtractor.isHLSURL(result.urls[1].normalizedURL), "M3U8 links should be detected")
        try expect(!URLExtractor.isSupportedURL("file:///tmp/video.mp4"), "Local file URLs should be rejected")
    }),
    ("URLExtractor identifies likely clipboard media", {
        try expect(URLExtractor.isLikelyMediaURL("https://youtu.be/abc123"), "YouTube links should prompt")
        try expect(URLExtractor.isLikelyMediaURL("https://cdn.example.com/master.m3u8?token=1"), "HLS links should prompt")
        try expect(URLExtractor.isLikelyMediaURL("https://cdn.example.com/video.mp4"), "Direct video links should prompt")
        try expect(!URLExtractor.isLikelyMediaURL("https://example.com/article"), "Ordinary web links should not prompt")
    }),
    ("URLExtractor removes YouTube mix parameters for single-track audio", {
        try expectEqual(
            URLExtractor.singleYouTubeVideoURL("https://www.youtube.com/watch?v=pu22yjU49Rw&list=RDR9ag38BwOP8&index=3"),
            "https://www.youtube.com/watch?v=pu22yjU49Rw",
            "Radio mix URLs should keep only the current video"
        )
    }),
    ("Browser capture requires confirmation and rejects wrapper pages", {
        let wrapper = try unwrap(URL(string: "pullr://add?url=https%3A%2F%2Fexample.com%2Fwatch%2Fepisode-1"), "Wrapper deep link should parse")
        try expect(BrowserCaptureSuggestion(deepLink: wrapper) == nil, "Wrapper pages should never become browser captures")

        let hls = try unwrap(URL(string: "pullr://add?url=https%3A%2F%2Fcdn.example.com%2Fmaster.m3u8&captureKind=hls&origin=https%3A%2F%2Fvideo.example.com&contentType=application%2Fvnd.apple.mpegurl&contentLength=123456&thumbnailURL=https%3A%2F%2Fimages.example.com%2Fepisode.jpg"), "HLS deep link should parse")
        let suggestion = try unwrap(BrowserCaptureSuggestion(deepLink: hls), "Detected HLS should become a pending confirmation")
        try expectEqual(suggestion.kind, "hls", "Capture kind should parse")
        try expectEqual(suggestion.originURL, "https://video.example.com", "Origin should parse")
        try expectEqual(suggestion.contentLength, 123456, "Response size should parse")
        try expectEqual(suggestion.thumbnailURL, "https://images.example.com/episode.jpg", "Poster thumbnail should parse")
    }),
    ("Browser preset deep links select an explicit preset", {
        let link = try unwrap(URL(string: "pullr://add?url=https%3A%2F%2Fyoutube.com%2Fwatch%3Fv%3Dabc&presetID=3A4B5C6D-7E8F-4091-A120-AAAAAAAAAAAA&start=1"), "Preset deep link should parse")
        let request = try unwrap(BrowserPresetRequest(deepLink: link), "Preset deep link should become a request")
        try expectEqual(request.url, "https://youtube.com/watch?v=abc", "Page URL should parse")
        try expectEqual(request.presetID, ExportPreset.Defaults.bestYouTubeAudio, "Best audio preset should parse")
        try expect(request.startImmediately, "Extension downloads should start immediately")
    }),
    ("Browser capture accepts only local Pullr thumbnails", {
        let appSupport = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let thumbnails = appSupport.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let thumbnail = thumbnails.appendingPathComponent("capture.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: thumbnail)
        try expectEqual(
            BrowserCaptureSuggestion.validatedThumbnailURL(thumbnail.absoluteString, applicationSupportDirectory: appSupport),
            thumbnail.absoluteString,
            "A native-host thumbnail inside Pullr storage should be accepted"
        )
        let outside = appSupport.appendingPathComponent("outside.jpg")
        try Data([0xFF]).write(to: outside)
        try expect(
            BrowserCaptureSuggestion.validatedThumbnailURL(outside.absoluteString, applicationSupportDirectory: appSupport) == nil,
            "Local files outside Pullr thumbnail storage should be rejected"
        )
    }),
    ("Season capture infers episode URLs and preserves progress", {
        var plan = try unwrap(
            SeasonCapturePlan(referrerURL: "https://anime.example/watch/that-time-123/ep-17"),
            "Episode pages should create a season plan"
        )
        try expectEqual(plan.title, "That Time 123", "Season title should come from the series slug")
        try expectEqual(plan.episodes.map(\.number), [17], "Initial plan should contain the current episode")
        plan.episodes[0].capturedURL = "https://cdn.example/episode17.mp4"
        plan.setRange(first: 15, last: 18)
        try expectEqual(plan.episodes.map(\.number), [15, 16, 17, 18], "Range should create ordered episode pages")
        try expectEqual(plan.episodes[2].capturedURL, "https://cdn.example/episode17.mp4", "Changing range should preserve captured episodes")
        try expectEqual(plan.episodes[0].pageURL, "https://anime.example/watch/that-time-123/ep-15", "Episode URL should use the inferred template")
    }),
    ("SeasonStore persists the active plan", {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("season.json")
        let store = SeasonStore(fileURL: fileURL)
        let plan = try unwrap(SeasonCapturePlan(referrerURL: "https://anime.example/watch/show/ep-3"), "Season plan should parse")
        store.save(plan)
        try expectEqual(store.load(), plan, "Season plan should survive relaunch")
        store.save(nil)
        try expect(store.load() == nil, "Clearing a season should remove persisted state")
    }),
    ("Season quality presets map to safe resolution caps", {
        let presets = Dictionary(uniqueKeysWithValues: ExportPreset.defaultPresets.map { ($0.id, $0) })
        try expectEqual(presets[SeasonQuality.storageSaver.presetID]?.maxHeight, 720, "Storage Saver should cap at 720p")
        try expectEqual(presets[SeasonQuality.balanced.presetID]?.maxHeight, 720, "Balanced should cap at 720p")
        try expectEqual(presets[SeasonQuality.maxResolution.presetID]?.maxHeight, 1080, "Max Resolution should cap at 1080p")
    }),
    ("MediaDeskLayout removes and bounds inspector", {
        try expectEqual(MediaDeskLayout.inspectorWidth(availableWidth: 716, isVisible: false), 0, "Hidden inspector should leave the layout")
        try expectEqual(MediaDeskLayout.inspectorWidth(availableWidth: 716, isVisible: true), 270, "Inspector should use its readable minimum")
        try expectEqual(MediaDeskLayout.inspectorWidth(availableWidth: 1_400, isVisible: true), 330, "Inspector should stop growing before it crowds content")
    }),
    ("URLExtractor detects playlists and duplicates", {
        let result = URLExtractor.extract(
            from: "https://youtube.com/playlist?list=PL123 https://youtube.com/playlist?list=PL123",
            existingURLs: []
        )
        try expectEqual(result.urls.count, 1, "One playlist should be added")
        try expect(result.urls[0].isPlaylist, "Playlist query should be detected")
        try expectEqual(result.duplicates, ["https://youtube.com/playlist?list=PL123"], "Duplicate should be reported")
    }),
    ("CommandBuilder emits default preset arguments", {
        let expected: [(String, [String])] = [
            ("Best MP4", ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]),
            ("1080p MP4", ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]),
            ("720p MP4", ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]),
            ("Best YouTube Audio", ["-f", "bestaudio/best", "-x", "--audio-format", "alac", "--no-playlist", "--extractor-args", "youtube:player_client=web_embedded,android_vr"]),
            ("Audio MP3", ["-x", "--audio-format", "mp3", "--audio-quality", "0"]),
            ("Audio M4A", ["-x", "--audio-format", "m4a"]),
            ("Original", ["-f", "best"])
        ]

        for (name, expectedArguments) in expected {
            let preset = try unwrap(ExportPreset.defaultPresets.first { $0.name == name }, "Missing preset \(name)")
            let arguments = try CommandBuilder.buildArguments(
                for: DownloadCommandRequest(
                    url: "https://youtu.be/abc123",
                    preset: preset,
                    outputFolder: "/tmp/Pullr Tests",
                    namingTemplate: "%(title)s.%(ext)s",
                    playlistOptions: PlaylistOptions(createPlaylistFolder: false),
                    ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                    playlistFolderName: nil,
                    playlistIndex: nil,
                    advancedArguments: []
                )
            )
            try expect(arguments.starts(with: ["--newline", "--ignore-config", "--ffmpeg-location", "/opt/homebrew/bin/ffmpeg", "--concurrent-fragments", "4"] + expectedArguments), "\(name) should use expected args")
            try expectEqual(Array(arguments.suffix(1)), ["https://youtu.be/abc123"], "\(name) should append URL last")
            try expect(!arguments.contains("|") && !arguments.contains(";"), "Arguments should not contain shell operators")
        }
    }),
    ("CommandBuilder emits playlist options", {
        let arguments = try CommandBuilder.buildArguments(
            for: DownloadCommandRequest(
                url: "https://youtube.com/playlist?list=PL123",
                preset: ExportPreset.defaultPresets[1],
                outputFolder: "/Downloads",
                namingTemplate: "%(title)s.%(ext)s",
                playlistOptions: PlaylistOptions(createPlaylistFolder: true, rangeStart: 3, rangeEnd: 8, reverseOrder: true),
                ffmpegPath: nil,
                playlistFolderName: nil,
                playlistIndex: nil,
                advancedArguments: ["--no-mtime"]
            )
        )
        try expect(arguments.contains("--playlist-items"), "Playlist range flag missing")
        try expect(arguments.contains("3:8"), "Playlist range missing")
        try expect(arguments.contains("--playlist-reverse"), "Reverse flag missing")
        try expect(arguments.contains("%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"), "Playlist folder template missing")
        try expect(arguments.contains("--ignore-config"), "Pullr should ignore external yt-dlp config files")
    }),
    ("CommandBuilder accepts direct M3U8 streams", {
        let url = "https://media.example.com/master.m3u8?token=abc"
        let referrer = "https://video.example.com/watch/123"
        let arguments = try CommandBuilder.buildArguments(
            for: DownloadCommandRequest(
                url: url,
                preset: ExportPreset.defaultPresets[0],
                outputFolder: "/Downloads",
                namingTemplate: "%(title)s.%(ext)s",
                playlistOptions: PlaylistOptions(),
                ffmpegPath: "/opt/homebrew/bin/ffmpeg",
                playlistFolderName: nil,
                playlistIndex: nil,
                advancedArguments: [],
                referrerURL: referrer,
                concurrentFragments: 8,
                userAgent: "Pullr Browser Test/1.0",
                originURL: "https://video.example.com/player/path",
                outputDiscriminator: "episode-17"
            )
        )
        try expectEqual(arguments.last, url, "M3U8 URL should be passed directly to yt-dlp")
        try expect(arguments.contains("--referer") && arguments.contains(referrer), "Captured streams should keep their referring page")
        try expect(arguments.contains("--user-agent") && arguments.contains("Pullr Browser Test/1.0"), "Captured streams should keep their browser user agent")
        try expect(arguments.contains("--add-headers") && arguments.contains("Origin:https://video.example.com"), "Captured streams should keep a validated Origin header")
        try expect(arguments.contains("--concurrent-fragments") && arguments.contains("8"), "M3U8 streams should use configured fragment concurrency")
        try expect(arguments.contains("%(title)s [episode-17].%(ext)s"), "Captured streams should use collision-proof output names")
        try expect(!arguments.contains("--playlist-items"), "M3U8 streams should not receive playlist options")
    }),
    ("CommandBuilder keeps playlist defaults off plain videos", {
        let arguments = try CommandBuilder.buildArguments(
            for: DownloadCommandRequest(
                url: "https://youtu.be/abc123",
                preset: ExportPreset.defaultPresets[0],
                outputFolder: "/Downloads",
                namingTemplate: "%(title)s.%(ext)s",
                playlistOptions: PlaylistOptions(createPlaylistFolder: true, rangeStart: 1, rangeEnd: 4, reverseOrder: true),
                ffmpegPath: nil,
                playlistFolderName: nil,
                playlistIndex: nil,
                advancedArguments: []
            )
        )
        try expect(!arguments.contains("--playlist-items"), "Plain videos should not receive playlist range")
        try expect(!arguments.contains("--playlist-reverse"), "Plain videos should not receive playlist reverse")
        try expect(arguments.contains("%(title)s.%(ext)s"), "Plain videos should use the normal output template")
        try expect(!arguments.contains { $0.contains("%(playlist_title)s") }, "Plain videos should not use a playlist folder template")
    }),
    ("CommandBuilder names expanded playlist downloads in a clean folder", {
        let arguments = try CommandBuilder.buildArguments(
            for: DownloadCommandRequest(
                url: "https://youtu.be/abc123",
                preset: ExportPreset.defaultPresets[0],
                outputFolder: "/Downloads",
                namingTemplate: "%(title)s.%(ext)s",
                playlistOptions: PlaylistOptions(createPlaylistFolder: true),
                ffmpegPath: nil,
                playlistFolderName: "My/Playlist:Name",
                playlistIndex: 7,
                advancedArguments: []
            )
        )

        try expect(arguments.contains("My - Playlist - Name/007 - %(title)s.%(ext)s"), "Expanded playlist output should use sanitized folder and index")
    }),
    ("YTDLPService parses progress and status", {
        let snapshot = try unwrap(YTDLPService.parseProgressLine("[download]  42.3% of 120.45MiB at 4.20MiB/s ETA 00:14"), "Progress should parse")
        try expect(abs(snapshot.progress - 0.423) < 0.0001, "Progress percentage should parse")
        try expectEqual(snapshot.speed, "4.20MiB/s", "Speed should parse")
        try expectEqual(snapshot.eta, "00:14", "ETA should parse")
        try expectEqual(YTDLPService.parseStatusLine("[youtube] abc: Downloading webpage"), .fetchingInfo, "Fetching status should parse")
        try expectEqual(YTDLPService.parseStatusLine("[Merger] Merging formats into \"file.mp4\""), .converting, "Converting status should parse")
    }),
    ("YTDLPService parses output paths and caps logs", {
        try expectEqual(YTDLPService.parseOutputPath("[download] Destination: /tmp/video.mp4"), "/tmp/video.mp4", "Destination path should parse")
        try expectEqual(YTDLPService.parseOutputPath("[Merger] Merging formats into \"/tmp/video.mp4\""), "/tmp/video.mp4", "Quoted path should parse")

        var item = DownloadItem(url: "https://youtu.be/abc", selectedPresetID: ExportPreset.Defaults.bestMP4)
        for index in 0..<200 {
            item.appendLog("line \(index)", limit: 20)
        }
        try expectEqual(item.logs.count, 20, "Logs should be capped")
        try expectEqual(item.logs.first, "line 180", "Old logs should be removed")
        try expectEqual(item.logs.last, "line 199", "Newest log should remain")
    }),
    ("YTDLPService retries a transient YouTube 403 once", {
        let logs = ["ERROR: unable to download video data: HTTP Error 403: Forbidden"]
        let youtubeURL = "https://www.youtube.com/watch?v=abc"
        try expect(YTDLPService.shouldRetryTransient403(url: youtubeURL, logs: logs, alreadyRetried: false), "First YouTube 403 should retry")
        try expect(!YTDLPService.shouldRetryTransient403(url: youtubeURL, logs: logs, alreadyRetried: true), "A repeated YouTube 403 should fail normally")
        try expect(!YTDLPService.shouldRetryTransient403(url: youtubeURL, logs: ["ERROR: Video unavailable"], alreadyRetried: false), "Other errors should not retry")
        try expect(!YTDLPService.shouldRetryTransient403(url: "https://example.com/audio", logs: logs, alreadyRetried: false), "Non-YouTube 403s should fail normally")
    }),
    ("PresetStore saves, loads, and resets", {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = PresetStore(fileURL: url)
        try expectEqual(store.load(), ExportPreset.defaultPresets, "Missing preset file should load defaults")

        var presets = ExportPreset.defaultPresets
        presets.append(ExportPreset(name: "Podcast", kind: .audio, audioFormat: .mp3))
        if let index = presets.firstIndex(where: { $0.id == ExportPreset.Defaults.bestYouTubeAudio }) {
            presets[index].customArguments = ["-f", "bestaudio/best", "-x", "--no-playlist"]
        }
        store.save(presets)
        let loaded = store.load()
        try expectEqual(loaded.last?.name, "Podcast", "Custom preset should persist")
        let bestAudio = try unwrap(loaded.first { $0.id == ExportPreset.Defaults.bestYouTubeAudio }, "Best audio preset should load")
        try expect(bestAudio.customArguments.contains("alac"), "Saved best audio preset should receive the Music-compatible format")
        try expect(bestAudio.customArguments.contains("youtube:player_client=web_embedded,android_vr"), "Saved best audio preset should receive current YouTube client args")
        try expectEqual(store.resetDefaults(), ExportPreset.defaultPresets, "Reset should restore defaults")
    }),
    ("ListeningHistoryStore reads native-host events and clears them", {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("pullr-listening-\(UUID().uuidString).jsonl")
        let event = ListeningEvent(
            id: UUID(),
            title: "Song",
            artist: "Artist",
            url: "https://youtube.com/watch?v=abc",
            videoID: "abc",
            seconds: 30,
            listenedAt: 1_700_000_000
        )
        var data = try JSONEncoder().encode(event)
        data.append(0x0A)
        try data.write(to: fileURL)
        let store = ListeningHistoryStore(fileURL: fileURL)
        try expectEqual(store.load(), [event], "Native-host JSONL should load")
        store.clear()
        try expect(store.load().isEmpty, "Cleared listening history should be empty")
    }),
    ("MusicLibraryService safely quotes import paths", {
        let script = MusicLibraryService.appleScript(for: "/tmp/Artist's \"Song\".opus")
        try expect(script.contains("Artist's \\\"Song\\\".opus"), "Quoted filenames should be escaped for AppleScript")
        try expect(!MusicLibraryService.didImport(.null()), "A silent Music no-op should not count as an import")
        try expect(MusicLibraryService.didImport(NSAppleEventDescriptor(string: "file track")), "A returned Music track should count as an import")
    }),
    ("AppSettings decodes old saved settings with new defaults", {
        let json = #"{"downloadFolder":"/Downloads","namingTemplate":"%(title)s.%(ext)s","duplicateHandling":"ignore","ytDLPPath":"","ffmpegPath":""}"#
        let data = try unwrap(json.data(using: .utf8), "JSON data should encode")
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(settings.maxConcurrentDownloads, 3, "Old settings should default to three parallel downloads")
        try expectEqual(settings.maxConcurrentFragments, 4, "Old settings should default to four parallel fragments")
        try expectEqual(settings.autoUpdateYTDLPOnLaunch, false, "Old settings should default auto update off")
    }),
    ("MetadataService parses video and playlist metadata", {
        let videoJSON = #"{"title":"Example Video","uploader":"Example Artist","thumbnail":"https://img.example/thumb.jpg","duration":1440.5,"width":1920,"height":1080,"filesize_approx":123456789,"format_note":"1080p","is_live":false,"has_drm":false}"#
        let video = try unwrap(MetadataService.parseMetadata(from: Data(videoJSON.utf8)), "Video metadata should parse")
        try expectEqual(video.title, "Example Video", "Video title should parse")
        try expectEqual(video.uploader, "Example Artist", "Uploader should parse")
        try expectEqual(video.thumbnailURL, "https://img.example/thumb.jpg", "Thumbnail should parse")
        try expectEqual(video.isPlaylist, false, "Video should not be playlist")
        try expectEqual(video.duration, 1440.5, "Duration should parse")
        try expectEqual(video.height, 1080, "Resolution should parse")
        try expectEqual(video.estimatedFileSize, 123456789, "Estimated file size should parse")
        try expectEqual(video.formatDescription, "1080p", "Format description should parse")

        let playlistJSON = #"{"_type":"playlist","title":"Example Playlist","channel":"Channel","entries":[{"id":"1"},{"id":"2"}]}"#
        let playlist = try unwrap(MetadataService.parseMetadata(from: Data(playlistJSON.utf8)), "Playlist metadata should parse")
        try expectEqual(playlist.title, "Example Playlist", "Playlist title should parse")
        try expectEqual(playlist.uploader, "Channel", "Channel fallback should parse")
        try expectEqual(playlist.isPlaylist, true, "Playlist should be detected")
        try expectEqual(playlist.playlistEntryCount, 2, "Playlist entry count should parse")
    }),
    ("MetadataService parses flat playlist entries", {
        let playlistJSON = #"""
        {
          "_type": "playlist",
          "title": "Example Playlist",
          "channel": "Playlist Channel",
          "entries": [
            {
              "id": "abc123",
              "title": "First Video",
              "uploader": "Uploader A",
              "thumbnails": [
                {"url": "https://img.example/small.jpg", "width": 120},
                {"url": "https://img.example/large.jpg", "width": 640}
              ]
            },
            {
              "url": "https://www.youtube.com/watch?v=def456",
              "title": "Second Video"
            },
            {
              "url": "https://vimeo.com/123",
              "title": "Vimeo Video"
            }
          ]
        }
        """#

        let entries = try unwrap(MetadataService.parsePlaylistEntries(from: Data(playlistJSON.utf8)), "Playlist entries should parse")
        try expectEqual(entries.count, 3, "HTTP playlist entries should be retained")
        try expectEqual(entries[0].url, "https://www.youtube.com/watch?v=abc123", "YouTube ID should become watch URL")
        try expectEqual(entries[0].title, "First Video", "Entry title should parse")
        try expectEqual(entries[0].uploader, "Uploader A", "Entry uploader should parse")
        try expectEqual(entries[0].thumbnailURL, "https://img.example/large.jpg", "Largest thumbnail should be selected")
        try expectEqual(entries[0].playlistIndex, 1, "Missing playlist index should fall back to position")
        try expectEqual(entries[1].url, "https://www.youtube.com/watch?v=def456", "Full entry URL should be kept")
        try expectEqual(entries[1].uploader, "Playlist Channel", "Playlist channel should be fallback uploader")
    }),
    ("QueueStore persists and restores active downloads as waiting", {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = QueueStore(fileURL: url)
        let item = DownloadItem(
            url: "https://youtu.be/abc",
            title: "Active",
            selectedPresetID: ExportPreset.Defaults.bestMP4,
            status: .paused,
            progress: 0.5,
            speed: "1MiB/s",
            eta: "00:30"
        )

        store.save([item])
        let restored = try unwrap(store.load().first, "Queue item should restore")
        try expectEqual(restored.status, .waiting, "Active item should restore as waiting")
        try expectEqual(restored.progress, 0, "Progress should reset after relaunch")
        try expectEqual(restored.title, "Active", "Metadata should remain")
    }),
    ("DownloadLogStore preserves logs before removal", {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let item = DownloadItem(
            url: "https://example.com/video.m3u8",
            selectedPresetID: ExportPreset.Defaults.bestMP4,
            logs: ["first line", "final error"]
        )
        try DownloadLogStore(directory: directory).archive(item)
        let data = try Data(contentsOf: directory.appendingPathComponent("\(item.id.uuidString).json"))
        let archived = try JSONDecoder().decode(DownloadItem.self, from: data)
        try expectEqual(archived.logs, item.logs, "Removing a download must preserve its complete activity log")
    }),
    ("DownloadLogStore keeps full timestamped redacted logs", {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DownloadLogStore(directory: directory)
        let itemID = UUID()
        for index in 0..<200 {
            try store.append(
                "line \(index) https://youtube.com/watch?v=abc&token=secret \(NSHomeDirectory())/Downloads/file.m4a",
                for: itemID,
                at: Date(timeIntervalSince1970: 0)
            )
        }

        let log = try String(contentsOf: store.logURL(for: itemID), encoding: .utf8)
        try expectEqual(log.split(separator: "\n").count, 200, "Durable logs must not use the UI line cap")
        try expect(log.contains("1970-01-01T00:00:00.000Z"), "Durable logs should be timestamped")
        try expect(log.contains("https://youtube.com/watch"), "Logs should keep the useful URL path")
        try expect(!log.contains("token=secret"), "Logs must redact URL queries")
        try expect(!log.contains(NSHomeDirectory()), "Logs must redact the home directory")
        try expect(log.contains("~/Downloads/file.m4a"), "Redacted paths should remain useful")
    }),
    ("DownloadQueueManager runs multiple processes concurrently", {
        let manager = DownloadQueueManager()
        let firstID = UUID()
        let secondID = UUID()
        let firstDone = DispatchSemaphore(value: 0)
        let secondDone = DispatchSemaphore(value: 0)

        manager.startDownload(
            itemID: firstID,
            ytDLPPath: "/bin/sleep",
            arguments: ["0.2"],
            eventHandler: { _ in },
            completion: { _ in firstDone.signal() }
        )
        manager.startDownload(
            itemID: secondID,
            ytDLPPath: "/bin/sleep",
            arguments: ["0.2"],
            eventHandler: { _ in },
            completion: { _ in secondDone.signal() }
        )

        let activeIDs = manager.activeItemIDs()
        try expect(activeIDs.contains(firstID), "First process should be active")
        try expect(activeIDs.contains(secondID), "Second process should be active")
        try expectEqual(activeIDs.count, 2, "Both processes should run concurrently")

        _ = firstDone.wait(timeout: .now() + 2)
        _ = secondDone.wait(timeout: .now() + 2)
        try expect(manager.activeItemIDs().isEmpty, "Processes should be removed after completion")
    }),
    ("DownloadQueueManager pauses and resumes a process", {
        let manager = DownloadQueueManager()
        let itemID = UUID()
        let done = DispatchSemaphore(value: 0)

        manager.startDownload(
            itemID: itemID,
            ytDLPPath: "/bin/sleep",
            arguments: ["0.3"],
            eventHandler: { _ in },
            completion: { _ in done.signal() }
        )

        try expect(manager.pauseDownload(itemID: itemID), "Process should pause")
        try expect(manager.activeItemIDs().contains(itemID), "Paused process should remain active")
        try expect(manager.resumeDownload(itemID: itemID), "Process should resume")

        _ = done.wait(timeout: .now() + 2)
        try expect(manager.activeItemIDs().isEmpty, "Resumed process should complete and be removed")
    })
]

var failures: [String] = []

for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures.append("FAIL \(name): \(error)")
    }
}

if failures.isEmpty {
    print("All \(tests.count) Pullr unit tests passed.")
} else {
    for failure in failures {
        print(failure)
    }
    exit(1)
}
