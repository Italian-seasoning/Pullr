import Foundation

struct WebsiteActivityEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var site: String
    var title: String
    var seconds: Double
    var recordedAt: Double
    var isYouTube: Bool

    var date: Date { Date(timeIntervalSince1970: recordedAt) }
}
