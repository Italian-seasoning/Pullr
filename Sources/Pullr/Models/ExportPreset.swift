import Foundation

enum PresetKind: String, Codable, CaseIterable, Identifiable {
    case video
    case audio
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .original: "Original"
        }
    }
}

enum AudioFormat: String, Codable, CaseIterable, Identifiable {
    case mp3
    case m4a
    case opus
    case wav

    var id: String { rawValue }
}

struct ExportPreset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: PresetKind
    var isDefault: Bool
    var isVisibleInDropdown: Bool
    var formatSelector: String?
    var maxHeight: Int?
    var audioFormat: AudioFormat?
    var audioQuality: String?
    var mergeOutputFormat: String?
    var forceSingleItem: Bool?
    var customArguments: [String]

    init(
        id: UUID = UUID(),
        name: String,
        kind: PresetKind,
        isDefault: Bool = false,
        isVisibleInDropdown: Bool = true,
        formatSelector: String? = nil,
        maxHeight: Int? = nil,
        audioFormat: AudioFormat? = nil,
        audioQuality: String? = nil,
        mergeOutputFormat: String? = nil,
        forceSingleItem: Bool? = nil,
        customArguments: [String] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isDefault = isDefault
        self.isVisibleInDropdown = isVisibleInDropdown
        self.formatSelector = formatSelector
        self.maxHeight = maxHeight
        self.audioFormat = audioFormat
        self.audioQuality = audioQuality
        self.mergeOutputFormat = mergeOutputFormat
        self.forceSingleItem = forceSingleItem
        self.customArguments = customArguments
    }
}

extension ExportPreset {
    enum Defaults {
        static let bestMP4 = UUID(uuidString: "A1B2C3D4-E5F6-47A8-9B10-111111111111")!
        static let mp41080 = UUID(uuidString: "B2C3D4E5-F6A7-48B9-8C20-222222222222")!
        static let mp4720 = UUID(uuidString: "C3D4E5F6-A7B8-49C0-8D30-333333333333")!
        static let bestYouTubeAudio = UUID(uuidString: "3A4B5C6D-7E8F-4091-A120-AAAAAAAAAAAA")!
        static let audioMP3 = UUID(uuidString: "D4E5F6A7-B8C9-4AD1-8E40-444444444444")!
        static let audioM4A = UUID(uuidString: "E5F6A7B8-C9D0-4BE2-8F50-555555555555")!
        static let original = UUID(uuidString: "F6A7B8C9-D0E1-4CF3-9060-666666666666")!
        static let storageSaver = UUID(uuidString: "07182839-4A5B-4C6D-8E70-777777777777")!
        static let balanced = UUID(uuidString: "1829394A-5B6C-4D7E-8F80-888888888888")!
        static let maxResolution = UUID(uuidString: "293A4B5C-6D7E-4F80-9010-999999999999")!
    }

    static let defaultPresets: [ExportPreset] = [
        ExportPreset(
            id: Defaults.bestMP4,
            name: "Best MP4",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*+ba/b",
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        ),
        ExportPreset(
            id: Defaults.mp41080,
            name: "1080p MP4",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*[height<=1080]+ba/b[height<=1080]",
            maxHeight: 1080,
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        ),
        ExportPreset(
            id: Defaults.mp4720,
            name: "720p MP4",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*[height<=720]+ba/b[height<=720]",
            maxHeight: 720,
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]
        ),
        ExportPreset(
            id: Defaults.bestYouTubeAudio,
            name: "Best YouTube Audio",
            kind: .audio,
            isDefault: true,
            formatSelector: "bestaudio/best",
            forceSingleItem: true,
            customArguments: [
                "-f", "bestaudio/best",
                "-x",
                "--audio-format", "alac",
                "--no-playlist",
                "--extractor-args", "youtube:player_client=web_embedded,android_vr"
            ]
        ),
        ExportPreset(
            id: Defaults.audioMP3,
            name: "Audio MP3",
            kind: .audio,
            isDefault: true,
            audioFormat: .mp3,
            audioQuality: "0",
            customArguments: ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        ),
        ExportPreset(
            id: Defaults.audioM4A,
            name: "Audio M4A",
            kind: .audio,
            isDefault: true,
            audioFormat: .m4a,
            customArguments: ["-x", "--audio-format", "m4a"]
        ),
        ExportPreset(
            id: Defaults.original,
            name: "Original",
            kind: .original,
            isDefault: true,
            formatSelector: "best",
            customArguments: ["-f", "best"]
        ),
        ExportPreset(
            id: Defaults.storageSaver,
            name: "Storage Saver · 720p",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*[height<=720]+ba/b[height<=720]",
            maxHeight: 720,
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*[height<=720]+ba/b[height<=720]", "-S", "res:720,+size,+br", "--merge-output-format", "mp4"]
        ),
        ExportPreset(
            id: Defaults.balanced,
            name: "Balanced · 720p",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*[height<=720]+ba/b[height<=720]",
            maxHeight: 720,
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]
        ),
        ExportPreset(
            id: Defaults.maxResolution,
            name: "Max Resolution · 1080p",
            kind: .video,
            isDefault: true,
            formatSelector: "bv*[height<=1080]+ba/b[height<=1080]",
            maxHeight: 1080,
            mergeOutputFormat: "mp4",
            customArguments: ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        )
    ]
}
