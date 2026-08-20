import Foundation

struct DownloadItem: Identifiable, Codable, Hashable {
    var id: UUID
    var url: String
    var title: String?
    var uploader: String?
    var thumbnailURL: String?
    var selectedPresetID: UUID
    var status: DownloadStatus
    var progress: Double
    var speed: String?
    var eta: String?
    var outputPath: String?
    var errorMessage: String?
    var createdAt: Date
    var completedAt: Date?
    var isPlaylist: Bool
    var playlistEntryCount: Int?
    var sourcePlaylistTitle: String?
    var playlistIndex: Int?
    var referrerURL: String?
    var userAgent: String?
    var originURL: String?
    var logs: [String]

    init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        uploader: String? = nil,
        thumbnailURL: String? = nil,
        selectedPresetID: UUID,
        status: DownloadStatus = .waiting,
        progress: Double = 0,
        speed: String? = nil,
        eta: String? = nil,
        outputPath: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        isPlaylist: Bool = false,
        playlistEntryCount: Int? = nil,
        sourcePlaylistTitle: String? = nil,
        playlistIndex: Int? = nil,
        referrerURL: String? = nil,
        userAgent: String? = nil,
        originURL: String? = nil,
        logs: [String] = []
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.uploader = uploader
        self.thumbnailURL = thumbnailURL
        self.selectedPresetID = selectedPresetID
        self.status = status
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.outputPath = outputPath
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isPlaylist = isPlaylist
        self.playlistEntryCount = playlistEntryCount
        self.sourcePlaylistTitle = sourcePlaylistTitle
        self.playlistIndex = playlistIndex
        self.referrerURL = referrerURL
        self.userAgent = userAgent
        self.originURL = originURL
        self.logs = logs
    }

    var displayTitle: String {
        title?.isEmpty == false ? title! : URL(string: url)?.host ?? "Untitled download"
    }

    var domain: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "youtube.com"
    }

    mutating func appendLog(_ line: String, limit: Int = 160) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        logs.append(line)
        if logs.count > limit {
            logs.removeFirst(logs.count - limit)
        }
    }
}
