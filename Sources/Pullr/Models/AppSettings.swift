import Foundation

enum DuplicateHandling: String, Codable, CaseIterable, Identifiable {
    case ignore
    case allow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ignore: "Ignore duplicates"
        case .allow: "Allow duplicates"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var downloadFolder: String
    var namingTemplate: String
    var duplicateHandling: DuplicateHandling
    var ytDLPPath: String
    var ffmpegPath: String
    var maxConcurrentDownloads: Int
    var maxConcurrentFragments: Int
    var autoUpdateYTDLPOnLaunch: Bool
    var playlistDefaults: PlaylistOptions
    var globalCustomArguments: [String]
    var showRawLogsByDefault: Bool

    enum CodingKeys: String, CodingKey {
        case downloadFolder
        case namingTemplate
        case duplicateHandling
        case ytDLPPath
        case ffmpegPath
        case maxConcurrentDownloads
        case maxConcurrentFragments
        case autoUpdateYTDLPOnLaunch
        case playlistDefaults
        case globalCustomArguments
        case showRawLogsByDefault
    }

    init(
        downloadFolder: String = AppSettings.defaultDownloadFolder,
        namingTemplate: String = "%(title)s.%(ext)s",
        duplicateHandling: DuplicateHandling = .ignore,
        ytDLPPath: String = "",
        ffmpegPath: String = "",
        maxConcurrentDownloads: Int = 3,
        maxConcurrentFragments: Int = 4,
        autoUpdateYTDLPOnLaunch: Bool = false,
        playlistDefaults: PlaylistOptions = PlaylistOptions(),
        globalCustomArguments: [String] = [],
        showRawLogsByDefault: Bool = false
    ) {
        self.downloadFolder = downloadFolder
        self.namingTemplate = namingTemplate
        self.duplicateHandling = duplicateHandling
        self.ytDLPPath = ytDLPPath
        self.ffmpegPath = ffmpegPath
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.maxConcurrentFragments = maxConcurrentFragments
        self.autoUpdateYTDLPOnLaunch = autoUpdateYTDLPOnLaunch
        self.playlistDefaults = playlistDefaults
        self.globalCustomArguments = globalCustomArguments
        self.showRawLogsByDefault = showRawLogsByDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default

        self.downloadFolder = try container.decodeIfPresent(String.self, forKey: .downloadFolder) ?? defaults.downloadFolder
        self.namingTemplate = try container.decodeIfPresent(String.self, forKey: .namingTemplate) ?? defaults.namingTemplate
        self.duplicateHandling = try container.decodeIfPresent(DuplicateHandling.self, forKey: .duplicateHandling) ?? defaults.duplicateHandling
        self.ytDLPPath = try container.decodeIfPresent(String.self, forKey: .ytDLPPath) ?? defaults.ytDLPPath
        self.ffmpegPath = try container.decodeIfPresent(String.self, forKey: .ffmpegPath) ?? defaults.ffmpegPath
        let decodedMaxConcurrentDownloads = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentDownloads)
        self.maxConcurrentDownloads = min(max(decodedMaxConcurrentDownloads ?? defaults.maxConcurrentDownloads, 1), 6)
        let decodedMaxConcurrentFragments = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentFragments)
        self.maxConcurrentFragments = min(max(decodedMaxConcurrentFragments ?? defaults.maxConcurrentFragments, 1), 16)
        self.autoUpdateYTDLPOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateYTDLPOnLaunch) ?? defaults.autoUpdateYTDLPOnLaunch
        self.playlistDefaults = try container.decodeIfPresent(PlaylistOptions.self, forKey: .playlistDefaults) ?? defaults.playlistDefaults
        self.globalCustomArguments = try container.decodeIfPresent([String].self, forKey: .globalCustomArguments) ?? defaults.globalCustomArguments
        self.showRawLogsByDefault = try container.decodeIfPresent(Bool.self, forKey: .showRawLogsByDefault) ?? defaults.showRawLogsByDefault
    }

    static var `default`: AppSettings {
        AppSettings()
    }

    static var defaultDownloadFolder: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
    }
}
