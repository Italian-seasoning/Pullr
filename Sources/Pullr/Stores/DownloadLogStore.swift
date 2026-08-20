import Foundation

final class DownloadLogStore {
    private let directory: URL
    let diagnosticsDirectory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
            self.diagnosticsDirectory = directory
        } else {
            let diagnostics = ((try? StorageLocation.applicationSupportDirectory()) ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Diagnostics", isDirectory: true)
            self.directory = diagnostics.appendingPathComponent("Downloads", isDirectory: true)
            self.diagnosticsDirectory = diagnostics
        }
    }

    func append(_ line: String, for itemID: UUID, at date: Date = Date()) throws {
        let line = sanitized(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = logURL(for: itemID)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("[\(Self.timestampFormatter.string(from: date))] \(line)\n".utf8))
    }

    func logURL(for itemID: UUID) -> URL {
        directory.appendingPathComponent("\(itemID.uuidString).log")
    }

    func archive(_ item: DownloadItem) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var item = item
        item.url = sanitized(item.url)
        item.thumbnailURL = item.thumbnailURL.map(sanitized)
        item.outputPath = item.outputPath.map(sanitized)
        item.errorMessage = item.errorMessage.map(sanitized)
        item.referrerURL = item.referrerURL.map(sanitized)
        item.originURL = item.originURL.map(sanitized)
        item.userAgent = nil
        item.logs = item.logs.map(sanitized)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(item)
        try data.write(to: directory.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
    }

    private func sanitized(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s\"'<>]+"#) else { return result }

        for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let rawURL = String(result[range])
            guard var components = URLComponents(string: rawURL) else { continue }
            components.query = nil
            components.fragment = nil
            if let redactedURL = components.string {
                result.replaceSubrange(range, with: redactedURL)
            }
        }
        return result
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
