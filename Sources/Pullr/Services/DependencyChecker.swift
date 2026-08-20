import Foundation

struct BinaryCheck: Hashable {
    var configuredPath: String
    var resolvedPath: String?
    var searchedPaths: [String]

    var isAvailable: Bool {
        resolvedPath != nil
    }
}

struct DependencyReport: Hashable {
    var ytDLP: BinaryCheck
    var ffmpeg: BinaryCheck

    var isReady: Bool {
        ytDLP.isAvailable && ffmpeg.isAvailable
    }
}

enum DependencyChecker {
    static func check(settings: AppSettings) -> DependencyReport {
        DependencyReport(
            ytDLP: checkBinary(
                name: "yt-dlp",
                configuredPath: settings.ytDLPPath,
                defaultCandidates: [
                    "/opt/homebrew/bin/yt-dlp",
                    "/usr/local/bin/yt-dlp",
                    "\(NSHomeDirectory())/.local/bin/yt-dlp"
                ]
            ),
            ffmpeg: checkBinary(
                name: "ffmpeg",
                configuredPath: settings.ffmpegPath,
                defaultCandidates: [
                    "/opt/homebrew/bin/ffmpeg",
                    "/usr/local/bin/ffmpeg"
                ]
            )
        )
    }

    private static func checkBinary(name: String, configuredPath: String, defaultCandidates: [String]) -> BinaryCheck {
        var candidates: [String] = []

        let configured = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            candidates.append(expandTilde(configured))
        }

        candidates += defaultCandidates.map(expandTilde)
        candidates += pathCandidates(for: name)

        var unique: [String] = []
        var seen = Set<String>()
        for candidate in candidates where !candidate.isEmpty && !seen.contains(candidate) {
            unique.append(candidate)
            seen.insert(candidate)
        }

        let resolved = unique.first { FileManager.default.isExecutableFile(atPath: $0) }
        return BinaryCheck(configuredPath: configuredPath, resolvedPath: resolved, searchedPaths: unique)
    }

    private static func pathCandidates(for name: String) -> [String] {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path
            .split(separator: ":")
            .map { String($0) }
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
