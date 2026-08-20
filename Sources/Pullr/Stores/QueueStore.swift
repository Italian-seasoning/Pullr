import Foundation

final class QueueStore {
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
            self.fileURL = directory.appendingPathComponent("queue.json")
        }
    }

    func load() -> [DownloadItem] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let items = try? decoder.decode([DownloadItem].self, from: data)
        else {
            return []
        }

        return items.map { item in
            var restored = item
            if [.fetchingInfo, .downloading, .paused, .converting].contains(restored.status) {
                restored.status = .waiting
                restored.progress = 0
                restored.speed = nil
                restored.eta = nil
                restored.errorMessage = "Reset after Pullr relaunched."
            }
            return restored
        }
    }

    func save(_ items: [DownloadItem]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
