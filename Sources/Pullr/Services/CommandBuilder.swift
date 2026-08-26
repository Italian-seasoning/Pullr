import Foundation

struct DownloadCommandRequest {
    var url: String
    var preset: ExportPreset
    var outputFolder: String
    var namingTemplate: String
    var playlistOptions: PlaylistOptions
    var ffmpegPath: String?
    var playlistFolderName: String?
    var playlistIndex: Int?
    var advancedArguments: [String]
    var referrerURL: String? = nil
    var concurrentFragments: Int = 4
    var userAgent: String? = nil
    var originURL: String? = nil
    var outputDiscriminator: String? = nil
}

enum CommandBuilderError: LocalizedError, Equatable {
    case emptyURL
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .emptyURL: "A download URL is required."
        case .unsupportedURL: "Pullr requires an HTTP or HTTPS link."
        }
    }
}

enum CommandBuilder {
    static func buildArguments(for request: DownloadCommandRequest) throws -> [String] {
        guard !request.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommandBuilderError.emptyURL
        }
        guard URLExtractor.isSupportedURL(request.url) else {
            throw CommandBuilderError.unsupportedURL
        }

        var arguments: [String] = ["--newline", "--ignore-config"]
        let isPlaylist = URLExtractor.extract(from: request.url).urls.first?.isPlaylist ?? false

        if let ffmpegPath = request.ffmpegPath?.trimmingCharacters(in: .whitespacesAndNewlines), !ffmpegPath.isEmpty {
            arguments += ["--ffmpeg-location", ffmpegPath]
        }

        if let referrer = request.referrerURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           URLExtractor.isSupportedURL(referrer) {
            arguments += ["--referer", referrer]
        }

        if let userAgent = request.userAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userAgent.isEmpty {
            let sanitized = String(userAgent.components(separatedBy: .newlines).joined().prefix(500))
            arguments += ["--user-agent", sanitized]
        }

        if let origin = normalizedOrigin(request.originURL) {
            arguments += ["--add-headers", "Origin:\(origin)"]
        }

        arguments += ["--concurrent-fragments", String(min(max(request.concurrentFragments, 1), 16))]

        arguments += presetArguments(for: request.preset)
        if request.preset.id == ExportPreset.Defaults.bestYouTubeAudio || request.preset.forceSingleItem == true {
            arguments.append("--no-playlist")
        }
        arguments += javaScriptRuntimeArguments()

        let outputFolder = request.outputFolder.isEmpty ? AppSettings.defaultDownloadFolder : request.outputFolder
        arguments += ["-P", outputFolder]
        arguments += [
            "-o",
            outputTemplate(
                namingTemplate: request.namingTemplate,
                includePlaylistFolder: isPlaylist && request.playlistOptions.createPlaylistFolder,
                playlistFolderName: request.playlistFolderName,
                playlistIndex: request.playlistIndex,
                outputDiscriminator: request.outputDiscriminator
            )
        ]

        if isPlaylist, let playlistItems = request.playlistOptions.playlistItemsArgument {
            arguments += ["--playlist-items", playlistItems]
        }

        if isPlaylist && request.playlistOptions.reverseOrder {
            arguments.append("--playlist-reverse")
        }

        arguments += request.advancedArguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        arguments.append(request.url)
        return arguments
    }

    static func presetArguments(for preset: ExportPreset) -> [String] {
        if !preset.customArguments.isEmpty {
            return preset.customArguments
        }

        switch preset.kind {
        case .video:
            let selector: String
            if let maxHeight = preset.maxHeight {
                selector = "bv*[height<=\(maxHeight)]+ba/b[height<=\(maxHeight)]"
            } else {
                selector = preset.formatSelector ?? "bv*+ba/b"
            }

            var args = ["-f", selector]
            if let mergeFormat = preset.mergeOutputFormat, !mergeFormat.isEmpty {
                args += ["--merge-output-format", mergeFormat]
            }
            return args

        case .audio:
            var args: [String] = []
            if let selector = preset.formatSelector, !selector.isEmpty {
                args += ["-f", selector]
            }
            args.append("-x")
            if let audioFormat = preset.audioFormat {
                args += ["--audio-format", audioFormat.rawValue]
            }
            if let audioQuality = preset.audioQuality, !audioQuality.isEmpty {
                args += ["--audio-quality", audioQuality]
            }
            return args

        case .original:
            return ["-f", preset.formatSelector ?? "best"]
        }
    }

    static func javaScriptRuntimeArguments(
        candidates: [String] = [
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno",
            "\(NSHomeDirectory())/.deno/bin/deno"
        ]
    ) -> [String] {
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return [] }
        return ["--js-runtimes", "deno:\(path)"]
    }

    private static func normalizedOrigin(_ value: String?) -> String? {
        guard
            let value,
            let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host
        else { return nil }

        var origin = "\(components.scheme!.lowercased())://\(host)"
        if let port = components.port { origin += ":\(port)" }
        return origin
    }

    private static func outputTemplate(
        namingTemplate: String,
        includePlaylistFolder: Bool,
        playlistFolderName: String?,
        playlistIndex: Int?,
        outputDiscriminator: String?
    ) -> String {
        let fallback = "%(title)s.%(ext)s"
        var base = namingTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback
            : namingTemplate
        if let outputDiscriminator, !outputDiscriminator.isEmpty {
            base = base.replacingOccurrences(of: ".%(ext)s", with: " [\(sanitizedPathComponent(outputDiscriminator))].%(ext)s")
        }

        if let playlistFolderName, !playlistFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prefix = playlistIndex.map { String(format: "%03d - ", max(1, $0)) } ?? ""
            return "\(sanitizedPathComponent(playlistFolderName))/\(prefix)\(base)"
        }

        if includePlaylistFolder {
            return "%(playlist_title)s/%(playlist_index)03d - \(base)"
        }

        return base
    }

    static func sanitizedPathComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0")
        let parts = value
            .components(separatedBy: invalid)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = parts.joined(separator: " - ")
        let collapsed = joined.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "Playlist" : trimmed
    }
}
