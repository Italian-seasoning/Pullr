import SwiftUI

struct DownloadsSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("Download Folder") {
                HStack {
                    TextField("Folder", text: $store.settings.downloadFolder)
                    Button("Choose") {
                        store.chooseDownloadFolder()
                    }
                }
            }

            Section("Naming") {
                TextField("Template", text: $store.settings.namingTemplate)
                Text("Example: %(title)s.%(ext)s")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Section("Duplicates") {
                Picker("Duplicate handling", selection: $store.settings.duplicateHandling) {
                    ForEach(DuplicateHandling.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Queue") {
                Stepper(value: $store.settings.maxConcurrentDownloads, in: 1...6) {
                    HStack {
                        Text("Parallel downloads")
                        Spacer()
                        Text("\(store.settings.maxConcurrentDownloads)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Text("Pullr starts up to this many yt-dlp processes at once. Keep this low on slow networks or large playlists.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                Stepper(value: $store.settings.maxConcurrentFragments, in: 1...16) {
                    HStack {
                        Text("Parallel HLS/DASH fragments")
                        Spacer()
                        Text("\(store.settings.maxConcurrentFragments)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Text("Controls fragments inside each stream download. Four is a reliable default; lower it on fragile servers.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .glassPanel(cornerRadius: 18)
    }
}
