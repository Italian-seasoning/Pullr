import SwiftUI

struct PlaylistSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("Playlist Defaults") {
                Toggle("Create playlist folders", isOn: $store.settings.playlistDefaults.createPlaylistFolder)
                Toggle("Reverse playlist order", isOn: $store.settings.playlistDefaults.reverseOrder)
            }

            Section("Default Range") {
                HStack {
                    TextField("Start", text: optionalIntBinding($store.settings.playlistDefaults.rangeStart))
                    TextField("End", text: optionalIntBinding($store.settings.playlistDefaults.rangeEnd))
                }
                Text("Leave blank to download the full playlist.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .glassPanel(cornerRadius: 18)
    }

    private func optionalIntBinding(_ binding: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.map(String.init) ?? "" },
            set: { value in
                binding.wrappedValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
    }
}
