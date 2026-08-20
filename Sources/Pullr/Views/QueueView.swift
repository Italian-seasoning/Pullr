import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isPasteSheetPresented = false

    var body: some View {
        VStack(spacing: 14) {
            if !store.dependencyReport.isReady {
                DependencyBanner()
            }

            if store.items.isEmpty {
                QueueEmptyState(isPasteSheetPresented: $isPasteSheetPresented)
            } else {
                switch store.queueViewMode {
                case .grid:
                    ClipGridView(items: store.items)
                case .list:
                    ClipListView(items: store.items)
                }
            }
        }
        .sheet(isPresented: $isPasteSheetPresented) {
            PasteURLsSheet()
                .environmentObject(store)
        }
    }
}

private struct DependencyBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(AppTheme.warning)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("yt-dlp or ffmpeg could not be found.")
                    .font(.callout.weight(.semibold))
                Text("Install them with Homebrew or choose custom binary paths in Settings.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button("Settings") {
                store.selectedSection = .settings
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .glassPanel(cornerRadius: 14, material: .thinMaterial)
    }
}

private struct QueueEmptyState: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPasteSheetPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(AppTheme.subtleAccent)
                .frame(width: 76, height: 76)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.18), lineWidth: 0.5)
                }

            VStack(spacing: 6) {
                Text("No downloads yet")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Copy a YouTube link, then add it from the clipboard or paste a batch.")
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button {
                    store.addFromClipboard()
                } label: {
                    Label("Add from Clipboard", systemImage: "plus.rectangle.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Button {
                    isPasteSheetPresented = true
                } label: {
                    Label("Paste URLs", systemImage: "text.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)

            Text("Only download content you own, have permission to download, or that is legally available offline.")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .glassPanel(cornerRadius: 22)
    }
}
