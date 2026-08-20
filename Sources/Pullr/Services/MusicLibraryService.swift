import AppKit
import Foundation

enum MusicLibraryImportError: LocalizedError {
    case missingFile
    case notImported
    case automation(String)

    var errorDescription: String? {
        switch self {
        case .missingFile: "The downloaded audio file could not be found."
        case .notImported: "Music did not import this audio format."
        case .automation(let message): "Music import failed: \(message)"
        }
    }
}

enum MusicLibraryService {
    static func importFile(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MusicLibraryImportError.missingFile
        }

        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: appleScript(for: path))?.executeAndReturnError(&errorInfo) else {
            let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "Automation permission was denied."
            throw MusicLibraryImportError.automation(message)
        }
        guard didImport(result) else {
            throw MusicLibraryImportError.notImported
        }
    }

    static func didImport(_ result: NSAppleEventDescriptor) -> Bool {
        result.descriptorType != typeNull
    }

    static func appleScript(for path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Music\" to add POSIX file \"\(escaped)\""
    }
}
