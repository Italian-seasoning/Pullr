import Foundation

final class ListeningHistoryStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? StorageLocation.applicationSupportDirectory())
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = directory.appendingPathComponent("listening-history.jsonl")
        }
    }

    func load() -> [ListeningEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8)
        else { return [] }

        return contents.split(separator: "\n")
            .compactMap { try? decoder.decode(ListeningEvent.self, from: Data($0.utf8)) }
            .filter { $0.seconds > 0 && $0.seconds <= 60 }
            .sorted { $0.listenedAt > $1.listenedAt }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
