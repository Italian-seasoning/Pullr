import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case downloads
    case playlists
    case listening
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .playlists: "Playlists"
        case .listening: "Listening"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: "arrow.down.to.line.compact"
        case .playlists: "list.bullet.rectangle"
        case .listening: "waveform"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

enum QueueViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Kind {
        case success
        case warning
        case error
        case info
    }

    var id = UUID()
    var message: String
    var kind: Kind
}

struct ClipboardSuggestion: Identifiable, Equatable {
    var id: String { url }
    var url: String

    var source: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "copied link"
    }
}

struct BrowserPresetRequest: Equatable {
    var url: String
    var presetID: UUID
    var startImmediately: Bool

    init?(deepLink: URL) {
        guard deepLink.scheme == "pullr", deepLink.host == "add" else { return nil }
        let queryItems = URLComponents(url: deepLink, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard queryItems.first(where: { $0.name == "captureKind" }) == nil,
              let url = queryItems.first(where: { $0.name == "url" || $0.name == "text" })?.value,
              URLExtractor.isSupportedURL(url),
              let presetValue = queryItems.first(where: { $0.name == "presetID" })?.value,
              let presetID = UUID(uuidString: presetValue)
        else { return nil }
        self.url = URLExtractor.singleYouTubeVideoURL(url)
        self.presetID = presetID
        self.startImmediately = ["1", "true"].contains(
            queryItems.first(where: { $0.name == "start" })?.value?.lowercased() ?? ""
        )
    }
}

struct BrowserCaptureSuggestion: Identifiable, Equatable {
    var id: String { url }
    var url: String
    var referrerURL: String?
    var userAgent: String?
    var kind: String
    var originURL: String?
    var contentType: String?
    var contentLength: Int64?
    var thumbnailURL: String?

    init?(deepLink: URL) {
        guard deepLink.scheme == "pullr" else { return nil }
        let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false)
        guard
            let url = components?.queryItems?.first(where: { $0.name == "url" || $0.name == "text" })?.value,
            URLExtractor.isSupportedURL(url),
            let kind = components?.queryItems?.first(where: { $0.name == "captureKind" })?.value,
            ["hls", "dash", "direct"].contains(kind)
        else { return nil }

        self.url = url
        self.referrerURL = components?.queryItems?.first { $0.name == "referrer" }?.value
        self.userAgent = components?.queryItems?.first { $0.name == "userAgent" }?.value
        self.kind = kind
        self.originURL = components?.queryItems?.first { $0.name == "origin" }?.value
        self.contentType = components?.queryItems?.first { $0.name == "contentType" }?.value
        self.contentLength = components?.queryItems?.first { $0.name == "contentLength" }?.value.flatMap(Int64.init)
        self.thumbnailURL = components?.queryItems?.first { $0.name == "thumbnailURL" }?.value.flatMap {
            Self.validatedThumbnailURL($0)
        }
    }

    var mediaHost: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "media stream"
    }

    var pageHost: String? {
        URL(string: referrerURL ?? "")?.host?.replacingOccurrences(of: "www.", with: "")
    }

    var formatName: String {
        switch kind {
        case "hls": "HLS"
        case "dash": "MPEG-DASH"
        case "direct": "Direct video"
        default: "Media stream"
        }
    }

    static func validatedThumbnailURL(_ value: String, applicationSupportDirectory: URL? = nil) -> String? {
        if URLExtractor.isSupportedURL(value) { return value }
        guard let url = URL(string: value), url.isFileURL else { return nil }
        let appSupport = applicationSupportDirectory ?? (try? StorageLocation.applicationSupportDirectory())
        guard let root = appSupport?.appendingPathComponent("Thumbnails", isDirectory: true).standardizedFileURL else { return nil }
        let file = url.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file.absoluteString
    }
}

enum BrowserCaptureProbeState: Equatable {
    case idle
    case loading
    case loaded(DownloadMetadata)
    case failed(String)
}
