import SwiftUI

struct SeasonManagerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var firstEpisode = 1
    @State private var lastEpisode = 1
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let plan = store.seasonPlan {
                VStack(spacing: 14) {
                    if let capture = store.browserCaptureSuggestion {
                        capturedStreamCard(capture)
                    }
                    controls(plan)
                    episodeList(plan)
                }
                .padding(18)
            } else {
                ContentUnavailableView(
                    "No season plan",
                    systemImage: "rectangle.stack.badge.play",
                    description: Text("Capture an episode and choose Plan season.")
                )
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 650)
        .background(AppTheme.baseBackground)
        .onAppear(perform: syncRange)
        .onChange(of: store.seasonPlan?.id) { _, _ in syncRange() }
        .onChange(of: firstEpisode) { _, value in
            lastEpisode = max(lastEpisode, value)
        }
        .confirmationDialog("Clear this season plan?", isPresented: $confirmClear) {
            Button("Clear Season Plan", role: .destructive) {
                store.clearSeasonPlan()
                dismiss()
            }
        } message: {
            Text("Downloads already in the queue will remain there.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.seasonPlan?.title ?? "Season Capture")
                    .font(.title2.weight(.semibold))
                Text(progressSummary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button("Open next episode") {
                store.openNextSeasonEpisode()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private func controls(_ plan: SeasonCapturePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Stepper("First: \(firstEpisode)", value: $firstEpisode, in: 1...999)
                    .frame(width: 140)
                Stepper("Last: \(lastEpisode)", value: $lastEpisode, in: firstEpisode...999)
                    .frame(width: 140)
                Button("Apply range") {
                    store.updateSeasonRange(first: firstEpisode, last: lastEpisode)
                }

                Spacer()

                Button("Clear plan", role: .destructive) {
                    confirmClear = true
                }
                .buttonStyle(.borderless)
            }

            Picker("Quality", selection: qualityBinding) {
                ForEach(SeasonQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)

            Text(plan.quality.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(14)
        .glassPanel(cornerRadius: 16, material: .thinMaterial)
    }

    private func capturedStreamCard(_ capture: BrowserCaptureSuggestion) -> some View {
        HStack(spacing: 12) {
            CaptureThumbnail(
                urlString: store.browserCaptureThumbnailURL,
                fallbackIcon: "checkmark.circle.fill"
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(capturedEpisodeNumber.map { "Episode \($0) stream found" } ?? "Episode stream found")
                    .font(.callout.weight(.semibold))
                Text("\(capture.formatName) · \(capture.mediaHost)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(store.browserCaptureProbeSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button("Dismiss") { store.dismissBrowserCapture() }
                .buttonStyle(.borderless)
            Button("Add episode") { store.acceptBrowserCapture() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .padding(14)
        .glassPanel(cornerRadius: 16, material: .ultraThinMaterial)
    }

    private func episodeList(_ plan: SeasonCapturePlan) -> some View {
        List(plan.episodes) { episode in
            HStack(spacing: 12) {
                Button {
                    store.toggleSeasonEpisode(episode.id)
                } label: {
                    Image(systemName: episode.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(episode.isSelected ? AppTheme.accent : AppTheme.secondaryText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(episode.isSelected ? "Exclude" : "Include") episode \(episode.number)")

                Text("Episode \(episode.number)")
                    .font(.callout.weight(.semibold))
                    .frame(width: 100, alignment: .leading)

                EpisodeCaptureStatus(episode: episode)

                Spacer()

                Button(episode.capturedURL == nil ? "Open & play" : "Open again") {
                    store.openSeasonEpisode(episode)
                }
                .buttonStyle(.bordered)
                .disabled(!episode.isSelected)
            }
            .padding(.vertical, 5)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .glassPanel(cornerRadius: 16, material: .thinMaterial)
    }

    private var qualityBinding: Binding<SeasonQuality> {
        Binding(
            get: { store.seasonPlan?.quality ?? .balanced },
            set: store.setSeasonQuality
        )
    }

    private var capturedEpisodeNumber: Int? {
        guard let referrer = store.browserCaptureSuggestion?.referrerURL else { return nil }
        return store.seasonPlan?.episodes.first { normalized($0.pageURL) == normalized(referrer) }?.number
    }

    private var progressSummary: String {
        guard let plan = store.seasonPlan else { return "Guided episode capture" }
        let selected = plan.episodes.filter(\.isSelected)
        let captured = selected.filter { $0.capturedURL != nil }.count
        return "\(captured) of \(selected.count) selected episodes captured"
    }

    private func syncRange() {
        firstEpisode = store.seasonPlan?.firstEpisode ?? 1
        lastEpisode = store.seasonPlan?.lastEpisode ?? firstEpisode
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct EpisodeCaptureStatus: View {
    @EnvironmentObject private var store: AppStore
    var episode: SeasonEpisode

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }

    private var item: DownloadItem? {
        guard let id = episode.downloadItemID else { return nil }
        return store.items.first { $0.id == id }
    }

    private var label: String {
        if let item { return item.status.title }
        if episode.capturedURL != nil { return "Captured" }
        return "Needs playback"
    }

    private var icon: String {
        if let item { return item.status.systemImage }
        return episode.capturedURL == nil ? "play.rectangle" : "checkmark.circle"
    }

    private var color: Color {
        guard let item else { return episode.capturedURL == nil ? AppTheme.secondaryText : AppTheme.success }
        return item.status == .failed ? AppTheme.danger : AppTheme.secondaryText
    }
}
