import AVFoundation
import Darwin
import Foundation

struct ProgressSnapshot: Equatable {
    var progress: Double
    var speed: String?
    var eta: String?
}

struct YTDLPResult: Equatable {
    var exitCode: Int32
}

enum YTDLPEvent {
    case log(String)
    case progress(ProgressSnapshot)
    case status(DownloadStatus)
    case outputPath(String)
    case error(String)
}

enum YTDLPServiceError: LocalizedError {
    case alreadyRunning
    case missingBinary
    case missingFFmpeg
    case conversionFailed(String)
    case cancelled
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A download is already running."
        case .missingBinary: "yt-dlp was not found. Choose a binary path in Settings."
        case .missingFFmpeg: "ffmpeg is required to save YouTube videos as H.265. Check Dependencies in Settings."
        case .conversionFailed(let message): "H.265 conversion failed: \(message) The source download was kept."
        case .cancelled: "The download was cancelled."
        case .launchFailed(let message): message
        }
    }
}

final class YTDLPService {
    static let outputPathPrefix = "__PULLR_OUTPUT__:"
    private let readQueue = DispatchQueue(label: "Pullr.YTDLPService.read")
    private let stateLock = NSLock()
    private var process: Process?
    private var isActive = false
    private var isCancelling = false
    private var isPaused = false

    var isRunning: Bool {
        stateLock.withLock { isActive }
    }

    func start(
        ytDLPPath: String,
        arguments: [String],
        hevcFFmpegPath: String? = nil,
        eventHandler: @escaping (YTDLPEvent) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) {
        let canStart = stateLock.withLock {
            guard !isActive else { return false }
            isActive = true
            isCancelling = false
            isPaused = false
            return true
        }
        guard canStart else {
            completion(.failure(YTDLPServiceError.alreadyRunning))
            return
        }

        let finish: (Result<YTDLPResult, Error>) -> Void = { result in
            let cancelled = self.stateLock.withLock {
                let cancelled = self.isCancelling
                self.isActive = false
                self.process = nil
                self.isCancelling = false
                self.isPaused = false
                return cancelled
            }
            completion(cancelled ? .failure(YTDLPServiceError.cancelled) : result)
        }

        guard FileManager.default.isExecutableFile(atPath: ytDLPPath) else {
            finish(.failure(YTDLPServiceError.missingBinary))
            return
        }
        if let hevcFFmpegPath, !FileManager.default.isExecutableFile(atPath: hevcFFmpegPath) {
            finish(.failure(YTDLPServiceError.missingFFmpeg))
            return
        }

        var outputPaths: [String] = []
        runProcess(executable: ytDLPPath, arguments: arguments, lineHandler: { line in
            if line.hasPrefix(Self.outputPathPrefix) {
                let path = String(line.dropFirst(Self.outputPathPrefix.count))
                if !outputPaths.contains(path) { outputPaths.append(path) }
            }
            self.emit(line: line, isError: false, eventHandler: eventHandler)
        }, completion: { result in
            guard case .success(let downloaded) = result, downloaded.exitCode == 0,
                  let hevcFFmpegPath else {
                finish(result)
                return
            }
            guard !outputPaths.isEmpty else {
                finish(.failure(YTDLPServiceError.conversionFailed("The final download path was unavailable.")))
                return
            }
            let paths = outputPaths
            Task { await self.convertToHEVC(paths: paths, ffmpegPath: hevcFFmpegPath, eventHandler: eventHandler, completion: finish) }
        })
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        lineHandler: @escaping (String) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) {
        let process = Process()
        let outputPipe = Pipe()
        let exited = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { _ in exited.signal() }

        do {
            try stateLock.withLock {
                guard !isCancelling else { throw YTDLPServiceError.cancelled }
                self.process = process
                try process.run()
            }
        } catch {
            completion(.failure(YTDLPServiceError.launchFailed(error.localizedDescription)))
            return
        }

        // Drain the pipe before completing, so the final path cannot race the
        // conversion or the queue's completed state. Decode complete UTF-8 lines.
        readQueue.async {
            let handle = outputPipe.fileHandleForReading
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let end = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    lineHandler(String(decoding: buffer[..<end], as: UTF8.self))
                    buffer.removeSubrange(...end)
                }
            }
            if !buffer.isEmpty { lineHandler(String(decoding: buffer, as: UTF8.self)) }
            // waitUntilExit can strand a run loop when the process was launched from Swift concurrency.
            exited.wait()
            try? handle.close()
            self.stateLock.withLock { self.process = nil }
            completion(.success(YTDLPResult(exitCode: process.terminationStatus)))
        }
    }

    static func hevcArguments(input: String, output: String) -> [String] {
        ["-hide_banner", "-nostdin", "-loglevel", "error", "-i", input,
         "-map", "0:v:0", "-map", "0:a?", "-map_metadata", "0",
         "-c:v", "hevc_videotoolbox", "-allow_sw", "1", "-q:v", "65", "-tag:v", "hvc1",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-n", output]
    }

    private func convertToHEVC(
        paths: [String],
        ffmpegPath: String,
        eventHandler: @escaping (YTDLPEvent) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) async {
        guard !stateLock.withLock({ isCancelling }) else {
            completion(.failure(YTDLPServiceError.cancelled))
            return
        }
        guard let path = paths.first else {
            completion(.success(YTDLPResult(exitCode: 0)))
            return
        }
        let source = URL(fileURLWithPath: path)
        let target = source.deletingPathExtension().appendingPathExtension("mp4")
        let keepSource = await Self.isCompatibleHEVCMP4(source)
        guard !stateLock.withLock({ isCancelling }) else {
            completion(.failure(YTDLPServiceError.cancelled))
            return
        }
        if keepSource {
            eventHandler(.outputPath(path))
            eventHandler(.log("Keeping existing H.265 MP4 without re-encoding."))
            await convertToHEVC(paths: Array(paths.dropFirst()), ffmpegPath: ffmpegPath, eventHandler: eventHandler, completion: completion)
            return
        }
        let temporary = source.deletingLastPathComponent().appendingPathComponent(".pullr-hevc-\(UUID().uuidString).mp4")
        guard source.path == target.path || !FileManager.default.fileExists(atPath: target.path) else {
            completion(.failure(YTDLPServiceError.conversionFailed("An MP4 with this name already exists.")))
            return
        }
        eventHandler(.status(.converting))
        eventHandler(.progress(ProgressSnapshot(progress: 1, speed: nil, eta: nil)))
        eventHandler(.log("Converting downloaded video to H.265 MP4…"))
        var lastLog = "ffmpeg could not encode the video."
        runProcess(executable: ffmpegPath, arguments: Self.hevcArguments(input: path, output: temporary.path), lineHandler: { line in
            if !line.isEmpty {
                lastLog = line
                eventHandler(.log(line))
            }
        }, completion: { result in
            defer { try? FileManager.default.removeItem(at: temporary) }
            if self.stateLock.withLock({ self.isCancelling }) {
                completion(.failure(YTDLPServiceError.cancelled))
                return
            }
            guard case .success(let encoded) = result, encoded.exitCode == 0 else {
                let message: String
                if case .failure(let error) = result { message = error.localizedDescription }
                else { message = lastLog }
                completion(.failure(YTDLPServiceError.conversionFailed(message)))
                return
            }
            do {
                if source.path == target.path {
                    guard Darwin.rename(temporary.path, target.path) == 0 else {
                        throw YTDLPServiceError.conversionFailed("Could not replace the source MP4.")
                    }
                } else {
                    try FileManager.default.moveItem(at: temporary, to: target)
                    try FileManager.default.removeItem(at: source)
                }
                eventHandler(.outputPath(target.path))
                eventHandler(.log("Saved H.265 video: \(target.lastPathComponent)"))
                Task { await self.convertToHEVC(paths: Array(paths.dropFirst()), ffmpegPath: ffmpegPath, eventHandler: eventHandler, completion: completion) }
            } catch {
                completion(.failure(error))
            }
        })
    }

    private static func isCompatibleHEVCMP4(_ source: URL) async -> Bool {
        guard source.pathExtension == "mp4" else { return false }
        do {
            let tracks = try await AVURLAsset(url: source).load(.tracks)
            var videoCount = 0
            for track in tracks {
                let type = track.mediaType
                let formats = try await track.load(.formatDescriptions)
                let codec: FourCharCode
                switch type {
                case .video:
                    videoCount += 1
                    codec = kCMVideoCodecType_HEVC
                case .audio:
                    codec = kAudioFormatMPEG4AAC
                default:
                    return false
                }
                guard !formats.isEmpty, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == codec }) else { return false }
            }
            return videoCount == 1
        } catch {
            return false
        }
    }

    func cancel() {
        stateLock.withLock {
            guard isActive else { return }
            isCancelling = true
            guard let process, process.isRunning else { return }
            if isPaused {
                Darwin.kill(process.processIdentifier, SIGCONT)
                isPaused = false
            }
            process.terminate()
        }
    }

    @discardableResult
    func pause() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let process, process.isRunning, !isPaused else { return false }
        let result = Darwin.kill(process.processIdentifier, SIGSTOP)
        if result == 0 {
            isPaused = true
        }
        return result == 0
    }

    @discardableResult
    func resume() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let process, process.isRunning, isPaused else { return false }
        let result = Darwin.kill(process.processIdentifier, SIGCONT)
        if result == 0 {
            isPaused = false
        }
        return result == 0
    }

    static func parseProgressLine(_ line: String) -> ProgressSnapshot? {
        guard line.contains("[download]"), line.contains("%") else { return nil }

        let pattern = #"([0-9]+(?:\.[0-9]+)?)%"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
            match.range(at: 1).location != NSNotFound
        else {
            return nil
        }

        let nsLine = line as NSString
        let percent = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
        let speed = firstCapture(in: line, pattern: #"at\s+([^\s]+)"#)
        let eta = firstCapture(in: line, pattern: #"ETA\s+([0-9:]+)"#)

        return ProgressSnapshot(progress: min(max(percent / 100, 0), 1), speed: speed, eta: eta)
    }

    static func parseStatusLine(_ line: String) -> DownloadStatus? {
        if line.contains("[Merger]") || line.contains("[ExtractAudio]") || line.localizedCaseInsensitiveContains("converting") {
            return .converting
        }

        if line.contains("[download]") && line.contains("%") {
            return .downloading
        }

        if line.contains("[youtube]") || line.localizedCaseInsensitiveContains("downloading webpage") {
            return .fetchingInfo
        }

        return nil
    }

    static func parseOutputPath(_ line: String) -> String? {
        if line.hasPrefix(outputPathPrefix) {
            return String(line.dropFirst(outputPathPrefix.count))
        }
        if let range = line.range(of: "Destination: ") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let firstQuote = line.firstIndex(of: "\""),
           let secondQuote = line[line.index(after: firstQuote)...].firstIndex(of: "\"") {
            return String(line[line.index(after: firstQuote)..<secondQuote])
        }

        return nil
    }

    static func shouldRetryTransient403(url: String, logs: [String], alreadyRetried: Bool) -> Bool {
        guard
            !alreadyRetried,
            let host = URL(string: url)?.host?.lowercased(),
            host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
        else {
            return false
        }

        return logs.suffix(20).contains {
            $0.localizedCaseInsensitiveContains("HTTP Error 403")
        }
    }

    private func emit(line: String, isError: Bool, eventHandler: @escaping (YTDLPEvent) -> Void) {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        eventHandler(.log(trimmed))

        if let progress = Self.parseProgressLine(trimmed) {
            eventHandler(.progress(progress))
        }

        if let status = Self.parseStatusLine(trimmed) {
            eventHandler(.status(status))
        }

        if let outputPath = Self.parseOutputPath(trimmed) {
            eventHandler(.outputPath(outputPath))
        }

        if isError || trimmed.localizedCaseInsensitiveContains("ERROR:") {
            eventHandler(.error(trimmed))
        }
    }

    private static func drainLines(from buffer: inout String, handler: (String) -> Void) {
        while let range = buffer.rangeOfCharacter(from: .newlines) {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(...range.lowerBound)
            handler(line)
        }
    }

    private static func string(in nsString: NSString, match: NSTextCheckingResult, index: Int) -> String? {
        guard match.numberOfRanges > index, match.range(at: index).location != NSNotFound else {
            return nil
        }
        return nsString.substring(with: match.range(at: index))
    }

    private static func firstCapture(in line: String, pattern: String) -> String? {
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
            match.range(at: 1).location != NSNotFound
        else {
            return nil
        }

        return (line as NSString).substring(with: match.range(at: 1))
    }
}
