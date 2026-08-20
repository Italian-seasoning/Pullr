import Foundation

final class PresetStore {
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
            self.fileURL = directory.appendingPathComponent("presets.json")
        }
    }

    func load() -> [ExportPreset] {
        guard
            let data = try? Data(contentsOf: fileURL),
            let presets = try? decoder.decode([ExportPreset].self, from: data),
            !presets.isEmpty
        else {
            return ExportPreset.defaultPresets
        }

        return reconcileDefaults(in: presets)
    }

    func save(_ presets: [ExportPreset]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(presets) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func resetDefaults() -> [ExportPreset] {
        let presets = ExportPreset.defaultPresets
        save(presets)
        return presets
    }

    private func reconcileDefaults(in presets: [ExportPreset]) -> [ExportPreset] {
        var byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })

        for defaultPreset in ExportPreset.defaultPresets {
            if defaultPreset.id == ExportPreset.Defaults.bestYouTubeAudio,
               var savedPreset = byID[defaultPreset.id] {
                savedPreset.formatSelector = defaultPreset.formatSelector
                savedPreset.forceSingleItem = defaultPreset.forceSingleItem
                savedPreset.customArguments = defaultPreset.customArguments
                byID[defaultPreset.id] = savedPreset
            } else if byID[defaultPreset.id] == nil {
                byID[defaultPreset.id] = defaultPreset
            }
        }

        let orderedDefaults = ExportPreset.defaultPresets.compactMap { byID.removeValue(forKey: $0.id) }
        let custom = presets.filter { !$0.isDefault && byID[$0.id] != nil }
        return orderedDefaults + custom
    }
}
