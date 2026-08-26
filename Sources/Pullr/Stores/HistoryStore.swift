import Foundation

final class HistoryStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? StorageLocation.applicationSupportDirectory())
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = directory.appendingPathComponent("history.json")
        }
    }

    func load() -> [HistoryItem] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let items = try? decoder.decode([HistoryItem].self, from: data)
        else {
            return []
        }

        return items.sorted { $0.completedAt > $1.completedAt }
    }

    func save(_ items: [HistoryItem]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
