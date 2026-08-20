import Foundation

enum SeasonQuality: String, Codable, CaseIterable, Identifiable {
    case storageSaver
    case balanced
    case maxResolution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storageSaver: "Storage Saver"
        case .balanced: "Balanced"
        case .maxResolution: "Max Resolution"
        }
    }

    var detail: String {
        switch self {
        case .storageSaver: "Up to 720p, prefers smaller files"
        case .balanced: "Up to 720p, best available quality"
        case .maxResolution: "Best available up to 1080p"
        }
    }

    var presetID: UUID {
        switch self {
        case .storageSaver: ExportPreset.Defaults.storageSaver
        case .balanced: ExportPreset.Defaults.balanced
        case .maxResolution: ExportPreset.Defaults.maxResolution
        }
    }
}

struct SeasonEpisode: Identifiable, Codable, Equatable {
    var id = UUID()
    var number: Int
    var pageURL: String
    var isSelected = true
    var capturedURL: String?
    var downloadItemID: UUID?
}

struct SeasonCapturePlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var urlPrefix: String
    var urlSuffix: String
    var firstEpisode: Int
    var lastEpisode: Int
    var quality: SeasonQuality = .balanced
    var episodes: [SeasonEpisode]

    init?(referrerURL: String) {
        let pattern = #"^(https?://.+/ep-)(\d+)(.*)$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: referrerURL, range: NSRange(referrerURL.startIndex..., in: referrerURL)),
            let prefixRange = Range(match.range(at: 1), in: referrerURL),
            let numberRange = Range(match.range(at: 2), in: referrerURL),
            let suffixRange = Range(match.range(at: 3), in: referrerURL),
            let number = Int(referrerURL[numberRange])
        else { return nil }

        let slug = URL(string: referrerURL)?.pathComponents.dropLast().last ?? "Season"
        self.title = slug.replacingOccurrences(of: "-", with: " ").capitalized
        self.urlPrefix = String(referrerURL[prefixRange])
        self.urlSuffix = String(referrerURL[suffixRange])
        self.firstEpisode = number
        self.lastEpisode = number
        self.episodes = [SeasonEpisode(number: number, pageURL: "\(urlPrefix)\(number)\(urlSuffix)")]
    }

    mutating func setRange(first: Int, last: Int) {
        firstEpisode = max(1, min(first, last))
        lastEpisode = max(firstEpisode, last)
        let existing = Dictionary(uniqueKeysWithValues: episodes.map { ($0.number, $0) })
        episodes = (firstEpisode...lastEpisode).map { number in
            existing[number] ?? SeasonEpisode(number: number, pageURL: "\(urlPrefix)\(number)\(urlSuffix)")
        }
    }
}
