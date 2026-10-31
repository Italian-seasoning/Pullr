import Foundation

enum QueueStoreError: LocalizedError {
    case unreadable(URL, String)
    case recoveryFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url, let reason):
            "The saved queue could not be read: \(reason)\nA recovery copy is preserved at \(url.path)."
        case .recoveryFailed(let url, let reason):
            "The saved queue could not be backed up: \(reason)\nThe original remains at \(url.path). Queue saves are blocked until it can be recovered; repair or move it and relaunch Pullr."
        }
    }
}

final class QueueStore {
    private let fileURL: URL
    private var writesBlocked = false
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
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = root.appendingPathComponent("Pullr/queue.json")
        }
    }

    func load() throws -> [DownloadItem] {
        let items: [DownloadItem]
        do {
            let data = try Data(contentsOf: fileURL)
            items = try decoder.decode([DownloadItem].self, from: data)
            writesBlocked = false
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            writesBlocked = false
            return []
        } catch {
            writesBlocked = true
            let recoveryURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("queue-recovery-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: fileURL, to: recoveryURL)
                writesBlocked = false
            } catch {
                throw QueueStoreError.recoveryFailed(fileURL, error.localizedDescription)
            }
            throw QueueStoreError.unreadable(recoveryURL, error.localizedDescription)
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

    func save(_ items: [DownloadItem]) throws {
        guard !writesBlocked else { throw QueueStoreError.recoveryFailed(fileURL, "Recovery has not succeeded.") }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
    }
}
