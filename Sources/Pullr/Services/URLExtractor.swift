import Foundation

struct ExtractedURL: Identifiable, Hashable {
    var id: String { normalizedURL }
    var normalizedURL: String
    var isPlaylist: Bool
}

struct URLExtractionResult: Equatable {
    var urls: [ExtractedURL]
    var duplicates: [String]
}

enum URLExtractor {
    private static let pattern = #"(?i)\b(https?://[^\s<>"']+|(?:(?:(?:www|m|music)\.)?youtube\.com|youtu\.be)/[^\s<>"']+)"#
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)]}\"'")

    static func extract(from text: String, existingURLs: Set<String> = []) -> URLExtractionResult {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return URLExtractionResult(urls: [], duplicates: [])
        }

        let nsText = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        var extracted: [ExtractedURL] = []
        var duplicates: [String] = []

        for match in matches {
            let raw = nsText.substring(with: match.range)
            guard let normalized = normalize(raw) else { continue }
            let isDuplicate = existingURLs.contains(normalized) || seen.contains(normalized)

            if isDuplicate {
                duplicates.append(normalized)
                continue
            }

            seen.insert(normalized)
            extracted.append(ExtractedURL(normalizedURL: normalized, isPlaylist: isPlaylistURL(normalized)))
        }

        return URLExtractionResult(urls: extracted, duplicates: duplicates)
    }

    static func isSupportedURL(_ string: String) -> Bool {
        normalize(string) != nil
    }

    static func singleYouTubeVideoURL(_ string: String) -> String {
        guard var components = URLComponents(string: string),
              let host = components.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
        else { return string }

        let videoID: String?
        if host == "youtu.be" {
            videoID = components.path.split(separator: "/").first.map(String.init)
            components.host = "www.youtube.com"
        } else {
            videoID = components.queryItems?.first(where: { $0.name == "v" })?.value
                ?? (components.path.hasPrefix("/shorts/") ? components.path.split(separator: "/").dropFirst().first.map(String.init) : nil)
        }
        guard let videoID, !videoID.isEmpty else { return string }
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        components.fragment = nil
        return components.url?.absoluteString ?? string
    }

    static func isHLSURL(_ string: String) -> Bool {
        guard let components = URLComponents(string: string) else { return false }
        return components.path.lowercased().hasSuffix(".m3u8")
    }

    static func isDASHURL(_ string: String) -> Bool {
        guard let components = URLComponents(string: string) else { return false }
        return components.path.lowercased().hasSuffix(".mpd")
    }

    static func isLikelyMediaURL(_ string: String) -> Bool {
        guard
            let normalized = normalize(string),
            let url = URL(string: normalized),
            let host = url.host?.lowercased()
        else {
            return false
        }

        if isHLSURL(normalized) || isDASHURL(normalized) {
            return true
        }

        let mediaExtensions = ["mp4", "m4v", "mov", "webm", "mkv", "mp3", "m4a", "aac"]
        if mediaExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        let mediaHosts = [
            "youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "twitch.tv",
            "instagram.com", "facebook.com", "fb.watch", "x.com", "twitter.com",
            "soundcloud.com", "dailymotion.com"
        ]
        return mediaHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func normalize(_ rawValue: String) -> String? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.trimmingCharacters(in: trailingPunctuation)

        if let explicitScheme = URLComponents(string: candidate)?.scheme?.lowercased(),
           explicitScheme != "http", explicitScheme != "https" {
            return nil
        }

        if !candidate.lowercased().hasPrefix("http://") && !candidate.lowercased().hasPrefix("https://") {
            candidate = "https://\(candidate)"
        }

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            let url = components.url
        else {
            return nil
        }

        return url.absoluteString
    }

    private static func isPlaylistURL(_ string: String) -> Bool {
        guard let components = URLComponents(string: string) else { return false }
        return components.queryItems?.contains { item in
            item.name == "list" && item.value?.isEmpty == false
        } ?? false
    }
}
