import Foundation

final class SeasonStore {
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
            self.fileURL = directory.appendingPathComponent("season.json")
        }
    }

    func load() -> SeasonCapturePlan? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(SeasonCapturePlan.self, from: data)
    }

    func save(_ plan: SeasonCapturePlan?) {
        guard let plan else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(plan) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
