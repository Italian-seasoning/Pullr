import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isInspectorPresented: Bool
    @State private var link = ""
    @State private var isPasteSheetPresented = false
    @FocusState private var linkFieldFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullControls
            compactControls
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glassPanel(cornerRadius: 23, material: .ultraThinMaterial)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .sheet(isPresented: $isPasteSheetPresented) {
            PasteURLsSheet()
                .environmentObject(store)
        }
    }

    private var fullControls: some View {
        HStack(spacing: 10) {
            linkEntry(minWidth: 250)

            Button("Add link", action: addLinks)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            addMenu

            if store.selectedSection == .downloads {
                Divider()
                    .frame(height: 20)
                inspectorButton
            }
            queueButton
        }
    }

    private var compactControls: some View {
        HStack(spacing: 8) {
            linkEntry(minWidth: 140)

            Button(action: addLinks) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Add link")
            .accessibilityLabel("Add link")

            Menu {
                Button("Add from Clipboard") {
                    store.addFromClipboard()
                }
                Button("Paste multiple links") {
                    isPasteSheetPresented = true
                }
                Button("Manage season") {
                    store.presentSeasonManager()
                }
                .disabled(store.seasonPlan == nil)
                Divider()
                Button(store.isQueueRunning ? "Stop downloads" : "Start downloads") {
                    store.startQueue()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .accessibilityLabel("More download actions")

            if store.selectedSection == .downloads {
                inspectorButton
            }
        }
    }

    private func linkEntry(minWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: detectedHLS ? "dot.radiowaves.left.and.right" : "link")
                .foregroundStyle(detectedHLS ? AppTheme.accent : AppTheme.tertiaryText)

            TextField("Paste a video, playlist, season, or M3U8 link", text: $link)
                .textFieldStyle(.plain)
                .focused($linkFieldFocused)
                .onSubmit(addLinks)

            if !link.isEmpty {
                Button {
                    link = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tertiaryText)
                .accessibilityLabel("Clear link")
            }
        }
        .padding(.horizontal, 11)
        .frame(minWidth: minWidth, minHeight: 34)
        .background(AppTheme.thumbnailFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(linkFieldFocused ? AppTheme.selectedStroke : AppTheme.panelStroke, lineWidth: 1)
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add from Clipboard") {
                store.addFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Paste multiple links") {
                isPasteSheetPresented = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("More ways to add links")
        .accessibilityLabel("More ways to add links")
    }

    private var inspectorButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .buttonStyle(.bordered)
        .help(isInspectorPresented ? "Hide inspector" : "Show inspector")
        .accessibilityLabel(isInspectorPresented ? "Hide inspector" : "Show inspector")
    }

    private var queueButton: some View {
        Button {
            store.startQueue()
        } label: {
            Label(store.isQueueRunning ? "Stop" : "Start", systemImage: store.isQueueRunning ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.bordered)
        .tint(store.isQueueRunning ? AppTheme.danger : AppTheme.accent)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var detectedHLS: Bool {
        URLExtractor.extract(from: link).urls.first.map { URLExtractor.isHLSURL($0.normalizedURL) } ?? false
    }

    private func addLinks() {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.selectedSection = .downloads
        store.addURLs(from: value, source: detectedHLS ? "M3U8 field" : "link field")
        link = ""
    }
}

struct PasteURLsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste multiple links")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("Add one link per line. Pullr will inspect each source before downloading.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(width: 520, height: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.thumbnailFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.panelStroke, lineWidth: 1)
                }
                .accessibilityLabel("Links to add")

            HStack {
                Text("Supports HTTP, HTTPS, M3U8, and sites handled by yt-dlp.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Add links") {
                    store.selectedSection = .downloads
                    store.addURLs(from: text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560)
        .background(AppTheme.panelFill)
        .preferredColorScheme(.dark)
    }
}
