import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section("Global yt-dlp Arguments") {
                TextEditor(text: globalArgumentsBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 130)
                    .scrollContentBackground(.hidden)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("One argument per line. Do not use this for access restrictions or protected content.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Section("Logs") {
                Toggle("Open raw logs by default", isOn: $store.settings.showRawLogsByDefault)

                Button("Open Diagnostics Folder") {
                    store.openDiagnosticsFolder()
                }
            }

            Section("Updates") {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

            Section("Reset") {
                Button("Reset Settings") {
                    store.resetSettings()
                }

                Button("Reset Default Presets") {
                    store.resetDefaultPresets()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .glassPanel(cornerRadius: 18)
    }

    private var globalArgumentsBinding: Binding<String> {
        Binding(
            get: { store.settings.globalCustomArguments.joined(separator: "\n") },
            set: { value in
                store.settings.globalCustomArguments = value
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
