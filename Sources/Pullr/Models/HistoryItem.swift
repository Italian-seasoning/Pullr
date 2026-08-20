import Foundation

struct HistoryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var url: String
    var presetName: String
    var completedAt: Date
    var outputPath: String?

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        presetName: String,
        completedAt: Date = Date(),
        outputPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.presetName = presetName
        self.completedAt = completedAt
        self.outputPath = outputPath
    }
}
