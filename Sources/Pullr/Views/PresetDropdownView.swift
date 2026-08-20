import SwiftUI

struct PresetDropdownView: View {
    @EnvironmentObject private var store: AppStore
    var item: DownloadItem

    var body: some View {
        Picker("Export Preset", selection: selection) {
            ForEach(store.visiblePresets) { preset in
                Text(preset.name).tag(preset.id)
            }
        }
        .labelsHidden()
        .frame(minWidth: 128)
        .accessibilityLabel("Export preset for \(item.displayTitle)")
    }

    private var selection: Binding<UUID> {
        Binding(
            get: {
                store.items.first(where: { $0.id == item.id })?.selectedPresetID ?? item.selectedPresetID
            },
            set: { presetID in
                store.setPreset(presetID, for: item.id)
            }
        )
    }
}
