import Foundation

struct ListeningEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var artist: String
    var url: String
    var videoID: String
    var seconds: Double
    var listenedAt: Double

    var date: Date { Date(timeIntervalSince1970: listenedAt) }
}
