import Foundation

enum DownloadStatus: String, Codable, CaseIterable, Identifiable {
    case waiting
    case fetchingInfo
    case downloading
    case paused
    case converting
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .fetchingInfo: "Fetching"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .converting: "Converting"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: "clock"
        case .fetchingInfo: "waveform"
        case .downloading: "arrow.down.circle"
        case .paused: "pause.circle"
        case .converting: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .waiting, .fetchingInfo, .downloading, .paused, .converting:
            false
        }
    }
}
