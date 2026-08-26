import SwiftUI

struct DependencySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section("Status") {
                DependencyStatusRow(
                    title: "yt-dlp",
                    check: store.dependencyReport.ytDLP,
                    installHint: "brew install yt-dlp"
                )

                DependencyStatusRow(
                    title: "ffmpeg",
                    check: store.dependencyReport.ffmpeg,
                    installHint: "brew install ffmpeg"
                )

                Button {
                    store.refreshDependencies()
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }

                Button {
                    store.updateYTDLP()
                } label: {
                    Label(store.isUpdatingYTDLP ? "Updating yt-dlp..." : "Update yt-dlp", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!store.dependencyReport.ytDLP.isAvailable || store.isUpdatingYTDLP)
            }

            Section("Binary Paths") {
                HStack {
                    TextField("yt-dlp path", text: $store.settings.ytDLPPath)
                    Button("Choose") {
                        store.chooseBinaryPath(for: "yt-dlp")
                    }
                }

                HStack {
                    TextField("ffmpeg path", text: $store.settings.ffmpegPath)
                    Button("Choose") {
                        store.chooseBinaryPath(for: "ffmpeg")
                    }
                }
            }

            Section("Auto Update") {
                Toggle("Update yt-dlp on launch", isOn: $store.settings.autoUpdateYTDLPOnLaunch)

                Text("Pullr uses Homebrew when it detects a Homebrew install; other installs use yt-dlp's built-in updater. The output below shows the result.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                if let output = store.lastYTDLPUpdateOutput, !output.isEmpty {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryText)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if !store.dependencyReport.isReady {
                Section("Setup") {
                    Text("Pullr needs yt-dlp and ffmpeg to download and convert media.")
                        .foregroundStyle(AppTheme.secondaryText)

                    CopyableCommand(command: "brew install yt-dlp ffmpeg")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .glassPanel(cornerRadius: 18)
    }
}

private struct DependencyStatusRow: View {
    var title: String
    var check: BinaryCheck
    var installHint: String

    var body: some View {
        HStack {
            Label(
                check.isAvailable ? "Found" : "Missing",
                systemImage: check.isAvailable ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .foregroundStyle(check.isAvailable ? AppTheme.success : AppTheme.warning)
            .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(check.resolvedPath ?? installHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }
}

private struct CopyableCommand: View {
    var command: String

    var body: some View {
        HStack {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
