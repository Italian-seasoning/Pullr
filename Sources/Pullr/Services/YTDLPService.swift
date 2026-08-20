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
    case cancelled
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A download is already running."
        case .missingBinary: "yt-dlp was not found. Choose a binary path in Settings."
        case .cancelled: "The download was cancelled."
        case .launchFailed(let message): message
        }
    }
}

final class YTDLPService {
    private let readQueue = DispatchQueue(label: "Pullr.YTDLPService.read")
    private var process: Process?
    private var isCancelling = false
    private var isPaused = false

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(
        ytDLPPath: String,
        arguments: [String],
        eventHandler: @escaping (YTDLPEvent) -> Void,
        completion: @escaping (Result<YTDLPResult, Error>) -> Void
    ) {
        guard process == nil || process?.isRunning == false else {
            completion(.failure(YTDLPServiceError.alreadyRunning))
            return
        }

        guard FileManager.default.isExecutableFile(atPath: ytDLPPath) else {
            completion(.failure(YTDLPServiceError.missingBinary))
            return
        }

        isCancelling = false
        isPaused = false

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: ytDLPPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var outputBuffer = ""
        var errorBuffer = ""

        let consume: (Data, Bool) -> Void = { [weak self] data, isError in
            guard let self, !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self.readQueue.async {
                if isError {
                    errorBuffer += chunk
                    Self.drainLines(from: &errorBuffer) { line in
                        self.emit(line: line, isError: true, eventHandler: eventHandler)
                    }
                } else {
                    outputBuffer += chunk
                    Self.drainLines(from: &outputBuffer) { line in
                        self.emit(line: line, isError: false, eventHandler: eventHandler)
                    }
                }
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle.availableData, false)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle.availableData, true)
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            self?.readQueue.async {
                if !outputBuffer.isEmpty {
                    self?.emit(line: outputBuffer, isError: false, eventHandler: eventHandler)
                    outputBuffer = ""
                }
                if !errorBuffer.isEmpty {
                    self?.emit(line: errorBuffer, isError: true, eventHandler: eventHandler)
                    errorBuffer = ""
                }
            }

            let wasCancelling = self?.isCancelling == true
            self?.process = nil
            self?.isCancelling = false
            self?.isPaused = false

            if wasCancelling {
                completion(.failure(YTDLPServiceError.cancelled))
            } else {
                completion(.success(YTDLPResult(exitCode: process.terminationStatus)))
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
            completion(.failure(YTDLPServiceError.launchFailed(error.localizedDescription)))
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        isCancelling = true
        if isPaused {
            Darwin.kill(process.processIdentifier, SIGCONT)
            isPaused = false
        }
        process.terminate()
    }

    @discardableResult
    func pause() -> Bool {
        guard let process, process.isRunning, !isPaused else { return false }
        let result = Darwin.kill(process.processIdentifier, SIGSTOP)
        if result == 0 {
            isPaused = true
        }
        return result == 0
    }

    @discardableResult
    func resume() -> Bool {
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
