import Combine
import SwiftUI

struct ListeningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isClearConfirmationPresented = false
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.listeningHistory.isEmpty && store.websiteActivity.isEmpty {
                ContentUnavailableView {
                    Label("No activity yet", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Enable hours tracking in the Pullr Chrome extension to begin.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ListeningMetric(title: "Website time", value: duration(websiteSeconds), icon: "globe")
                            ListeningMetric(title: "Today", value: duration(todayWebsiteSeconds), icon: "calendar")
                            ListeningMetric(title: "YouTube", value: duration(youtubeSeconds), icon: "play.rectangle")
                        }

                        HStack {
                            Text("Most visited")
                                .font(.headline)
                            Spacer()
                            Button("Clear", role: .destructive) {
                                isClearConfirmationPresented = true
                            }
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(sites.prefix(50)) { site in
                                HStack(spacing: 12) {
                                    Image(systemName: site.isYouTube ? "play.rectangle.fill" : "globe")
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(site.isYouTube ? "YouTube" : site.site)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(site.isYouTube && !site.title.isEmpty ? site.title : site.site)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(duration(site.seconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                .padding(10)
                                .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }

                        if !tracks.isEmpty {
                            Text("Most played on YouTube")
                                .font(.headline)
                            LazyVStack(spacing: 8) {
                                ForEach(tracks.prefix(20)) { track in
                                    HStack {
                                        Image(systemName: "music.note")
                                            .foregroundStyle(AppTheme.accent)
                                        Text(track.title).lineLimit(1)
                                        Spacer()
                                        Text(duration(track.seconds))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    .padding(10)
                                    .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { store.refreshListeningHistory() }
        .onReceive(refreshTimer) { _ in store.refreshListeningHistory() }
        .confirmationDialog("Clear all activity history?", isPresented: $isClearConfirmationPresented) {
            Button("Clear Activity History", role: .destructive) {
                store.clearListeningHistory()
            }
        }
    }

    private var websiteSeconds: Double {
        store.websiteActivity.reduce(0) { $0 + $1.seconds }
    }

    private var todayWebsiteSeconds: Double {
        store.websiteActivity
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.seconds }
    }

    private var youtubeSeconds: Double {
        store.websiteActivity.filter(\.isYouTube).reduce(0) { $0 + $1.seconds }
    }

    private var sites: [WebsiteSiteSummary] {
        Dictionary(grouping: store.websiteActivity, by: \.site)
            .compactMap { site, events in
                guard let latest = events.max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
                return WebsiteSiteSummary(
                    site: site,
                    title: latest.title,
                    seconds: events.reduce(0) { $0 + $1.seconds },
                    isYouTube: latest.isYouTube
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private var totalSeconds: Double {
        store.listeningHistory.reduce(0) { $0 + $1.seconds }
    }

    private var todaySeconds: Double {
        store.listeningHistory
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.seconds }
    }

    private var tracks: [ListeningTrackSummary] {
        Dictionary(grouping: store.listeningHistory) { event in
            event.videoID.isEmpty ? event.url : event.videoID
        }
        .compactMap { _, events in
            guard let latest = events.max(by: { $0.listenedAt < $1.listenedAt }) else { return nil }
            return ListeningTrackSummary(
                id: latest.videoID.isEmpty ? latest.url : latest.videoID,
                title: latest.title,
                artist: latest.artist,
                url: latest.url,
                seconds: events.reduce(0) { $0 + $1.seconds }
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private func duration(_ seconds: Double) -> String {
        if seconds >= 3_600 { return String(format: "%.1f h", seconds / 3_600) }
        return "\(max(1, Int(seconds / 60))) min"
    }
}

private struct ListeningTrackSummary: Identifiable {
    var id: String
    var title: String
    var artist: String
    var url: String
    var seconds: Double
}

private struct WebsiteSiteSummary: Identifiable {
    var id: String { site }
    var site: String
    var title: String
    var seconds: Double
    var isYouTube: Bool
}

private struct ListeningMetric: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
