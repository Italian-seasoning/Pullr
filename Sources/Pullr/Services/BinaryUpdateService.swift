import Foundation

struct BinaryUpdateResult: Equatable {
    var exitCode: Int32
    var output: String
}

enum BinaryUpdateServiceError: LocalizedError {
    case missingBinary
    case alreadyRunning
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary: "yt-dlp was not found. Choose a binary path in Settings."
        case .alreadyRunning: "yt-dlp update is already running."
        case .launchFailed(let message): message
        }
    }
}

final class BinaryUpdateService {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func updateYTDLP(
        ytDLPPath: String,
        completion: @escaping (Result<BinaryUpdateResult, Error>) -> Void
    ) {
        guard process?.isRunning != true else {
            completion(.failure(BinaryUpdateServiceError.alreadyRunning))
            return
        }

        guard FileManager.default.isExecutableFile(atPath: ytDLPPath) else {
            completion(.failure(BinaryUpdateServiceError.missingBinary))
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ytDLPPath)
        process.arguments = ["-U"]
        process.standardOutput = pipe
        process.standardError = pipe

        var output = ""
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            output += chunk
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            if let data = try? pipe.fileHandleForReading.readToEnd(), let tail = String(data: data, encoding: .utf8) {
                output += tail
            }
            self?.process = nil
            completion(.success(BinaryUpdateResult(exitCode: process.terminationStatus, output: output)))
        }

        do {
            try process.run()
            self.process = process
        } catch {
            self.process = nil
            completion(.failure(BinaryUpdateServiceError.launchFailed(error.localizedDescription)))
        }
    }
}
