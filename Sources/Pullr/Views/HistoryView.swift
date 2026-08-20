import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(spacing: 10) {
            if !store.history.isEmpty {
                HStack {
                    Text("\(store.history.count) completed download\(store.history.count == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                    Button("Clear history", role: .destructive) {
                        isClearConfirmationPresented = true
                    }
                }
            }

            if store.history.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Completed downloads will appear here.")
                        .font(.title3.weight(.semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 22)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.history) { item in
                            HistoryRow(item: item)
                        }
                    }
                    .padding(2)
                }
            }
        }
        .confirmationDialog(
            "Clear download history?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                store.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes history entries only. Downloaded files stay on your Mac.")
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var store: AppStore
    var item: HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(AppTheme.success)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.presetName)
                    Text(item.completedAt, format: .dateTime.month().day().hour().minute())
                    if let outputPath = item.outputPath {
                        Text(outputPath)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            }

            Spacer()

            Button {
                store.openInFinder(path: item.outputPath)
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .disabled(item.outputPath == nil)

            Button {
                store.importHistoryItemToMusic(item)
            } label: {
                Label("Music", systemImage: "music.note")
            }
            .disabled(item.outputPath == nil)

            Button {
                store.redownload(item)
            } label: {
                Label("Re-download", systemImage: "arrow.clockwise")
            }

            Button {
                store.removeHistory(item)
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove from history")
            .accessibilityLabel("Remove \(item.title) from history")
        }
        .buttonStyle(.borderless)
        .padding(12)
        .glassPanel(cornerRadius: 14, material: .thinMaterial)
    }
}
