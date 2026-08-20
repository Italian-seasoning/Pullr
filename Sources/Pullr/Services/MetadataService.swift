import Foundation

struct DownloadMetadata: Equatable {
    var title: String?
    var uploader: String?
    var thumbnailURL: String?
    var isPlaylist: Bool
    var playlistEntryCount: Int?
    var duration: Double?
    var width: Int?
    var height: Int?
    var estimatedFileSize: Int64?
    var formatDescription: String?
    var isLive: Bool
    var hasDRM: Bool
}

struct PlaylistEntryMetadata: Equatable {
    var url: String
    var title: String?
    var uploader: String?
    var thumbnailURL: String?
    var playlistIndex: Int?
}

enum MetadataServiceError: LocalizedError {
    case missingBinary
    case invalidJSON
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary: "yt-dlp was not found. Choose a binary path in Settings."
        case .invalidJSON: "yt-dlp returned metadata Pullr could not read."
        case .launchFailed(let message): message
        }
    }
}

final class MetadataService {
    func fetchMetadata(
        ytDLPPath: String,
        url: String,
        referrerURL: String? = nil,
        userAgent: String? = nil,
        originURL: String? = nil,
        completion: @escaping (Result<DownloadMetadata, Error>) -> Void
    ) {
        guard FileManager.default.isExecutableFile(atPath: ytDLPPath) else {
            completion(.failure(MetadataServiceError.missingBinary))
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ytDLPPath)
        var arguments = [
            "--dump-single-json",
            "--ignore-config",
            "--skip-download",
            "--no-warnings",
            "--flat-playlist"
        ]
        if let referrerURL, URLExtractor.isSupportedURL(referrerURL) {
            arguments += ["--referer", referrerURL]
        }
        if let userAgent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines), !userAgent.isEmpty {
            arguments += ["--user-agent", String(userAgent.components(separatedBy: .newlines).joined().prefix(500))]
        }
        if let origin = Self.normalizedOrigin(originURL) {
            arguments += ["--add-headers", "Origin:\(origin)"]
        }
        arguments.append(url)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputQueue = DispatchQueue(label: "Pullr.MetadataService.output")
        var outputData = Data()
        var errorData = Data()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                outputData.append(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                errorData.append(data)
            }
        }

        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            outputQueue.async {
                if let tail = try? outputPipe.fileHandleForReading.readToEnd() {
                    outputData.append(tail)
                }
                if let tail = try? errorPipe.fileHandleForReading.readToEnd() {
                    errorData.append(tail)
                }

                if process.terminationStatus == 0, let metadata = Self.parseMetadata(from: outputData) {
                    completion(.success(metadata))
                } else {
                    let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(MetadataServiceError.launchFailed(message?.isEmpty == false ? message! : "Metadata fetch failed.")))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(MetadataServiceError.launchFailed(error.localizedDescription)))
        }
    }

    func fetchPlaylistEntries(
        ytDLPPath: String,
        url: String,
        referrerURL: String? = nil,
        completion: @escaping (Result<[PlaylistEntryMetadata], Error>) -> Void
    ) {
        guard FileManager.default.isExecutableFile(atPath: ytDLPPath) else {
            completion(.failure(MetadataServiceError.missingBinary))
            return
        }

        runDumpJSON(ytDLPPath: ytDLPPath, url: url, referrerURL: referrerURL) { result in
            switch result {
            case .success(let data):
                if let entries = Self.parsePlaylistEntries(from: data) {
                    completion(.success(entries))
                } else {
                    completion(.failure(MetadataServiceError.invalidJSON))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func parseMetadata(from data: Data) -> DownloadMetadata? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let entries = object["entries"] as? [[String: Any]]
        let title = stringValue(object["title"])
        let uploader = stringValue(object["uploader"])
            ?? stringValue(object["channel"])
            ?? stringValue(object["creator"])
        let thumbnail = bestThumbnail(from: object)
        let isPlaylist = entries != nil || stringValue(object["_type"]) == "playlist"
        let formats = object["formats"] as? [[String: Any]] ?? []
        let largestVideoFormat = formats.max {
            (intValue($0["height"]) ?? 0) < (intValue($1["height"]) ?? 0)
        }
        let formatDescription = stringValue(object["format_note"])
            ?? stringValue(object["format"])
            ?? stringValue(object["ext"])?.uppercased()

        return DownloadMetadata(
            title: title,
            uploader: uploader,
            thumbnailURL: thumbnail,
            isPlaylist: isPlaylist,
            playlistEntryCount: entries?.count,
            duration: doubleValue(object["duration"]),
            width: intValue(object["width"]) ?? largestVideoFormat.flatMap { intValue($0["width"]) },
            height: intValue(object["height"]) ?? largestVideoFormat.flatMap { intValue($0["height"]) },
            estimatedFileSize: int64Value(object["filesize_approx"])
                ?? int64Value(object["filesize"])
                ?? largestVideoFormat.flatMap { int64Value($0["filesize_approx"]) ?? int64Value($0["filesize"]) },
            formatDescription: formatDescription,
            isLive: boolValue(object["is_live"]) ?? false,
            hasDRM: boolValue(object["has_drm"]) ?? false
        )
    }

    static func parsePlaylistEntries(from data: Data) -> [PlaylistEntryMetadata]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = object["entries"] as? [[String: Any]]
        else {
            return nil
        }

        return entries.enumerated().compactMap { offset, entry in
            guard let url = playlistEntryURL(from: entry), URLExtractor.isSupportedURL(url) else {
                return nil
            }

            return PlaylistEntryMetadata(
                url: url,
                title: stringValue(entry["title"]),
                uploader: stringValue(entry["uploader"])
                    ?? stringValue(entry["channel"])
                    ?? stringValue(entry["creator"])
                    ?? stringValue(object["uploader"])
                    ?? stringValue(object["channel"]),
                thumbnailURL: bestThumbnail(from: entry),
                playlistIndex: intValue(entry["playlist_index"])
                    ?? intValue(entry["playlist_autonumber"])
                    ?? offset + 1
            )
        }
    }

    private func runDumpJSON(
        ytDLPPath: String,
        url: String,
        referrerURL: String?,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ytDLPPath)
        var arguments = [
            "--dump-single-json",
            "--skip-download",
            "--no-warnings",
            "--flat-playlist"
        ]
        if let referrerURL, URLExtractor.isSupportedURL(referrerURL) {
            arguments += ["--referer", referrerURL]
        }
        arguments.append(url)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputQueue = DispatchQueue(label: "Pullr.MetadataService.dumpJSON")
        var outputData = Data()
        var errorData = Data()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                outputData.append(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.async {
                errorData.append(data)
            }
        }

        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            outputQueue.async {
                if let tail = try? outputPipe.fileHandleForReading.readToEnd() {
                    outputData.append(tail)
                }
                if let tail = try? errorPipe.fileHandleForReading.readToEnd() {
                    errorData.append(tail)
                }

                if process.terminationStatus == 0 {
                    completion(.success(outputData))
                } else {
                    let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(MetadataServiceError.launchFailed(message?.isEmpty == false ? message! : "Metadata fetch failed.")))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(MetadataServiceError.launchFailed(error.localizedDescription)))
        }
    }

    private static func bestThumbnail(from object: [String: Any]) -> String? {
        if let thumbnail = stringValue(object["thumbnail"]) {
            return thumbnail
        }

        guard let thumbnails = object["thumbnails"] as? [[String: Any]] else {
            return nil
        }

        return thumbnails
            .compactMap { thumbnail -> (url: String, width: Int) in
                let url = stringValue(thumbnail["url"]) ?? ""
                let width = thumbnail["width"] as? Int ?? 0
                return (url, width)
            }
            .filter { !$0.url.isEmpty }
            .sorted { $0.width > $1.width }
            .first?
            .url
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = stringValue(value) {
            return Int(string)
        }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
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

    private static func playlistEntryURL(from entry: [String: Any]) -> String? {
        if let webpageURL = stringValue(entry["webpage_url"]) {
            return webpageURL
        }

        if let url = stringValue(entry["url"]), url.hasPrefix("http") {
            return url
        }

        if let id = stringValue(entry["id"]) ?? stringValue(entry["url"]) {
            return "https://www.youtube.com/watch?v=\(id)"
        }

        return nil
    }
}
