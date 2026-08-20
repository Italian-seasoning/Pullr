import Combine
import SwiftUI

struct ListeningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isClearConfirmationPresented = false
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.listeningHistory.isEmpty {
                ContentUnavailableView {
                    Label("No listening time yet", systemImage: "waveform")
                } description: {
                    Text("Play music on YouTube with the Pullr extension enabled.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ListeningMetric(title: "Total listening", value: duration(totalSeconds), icon: "headphones")
                            ListeningMetric(title: "Today", value: duration(todaySeconds), icon: "calendar")
                            ListeningMetric(title: "Songs", value: "\(tracks.count)", icon: "music.note.list")
                        }

                        HStack {
                            Text("Most played")
                                .font(.headline)
                            Spacer()
                            Button("Clear", role: .destructive) {
                                isClearConfirmationPresented = true
                            }
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(tracks.prefix(50)) { track in
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(track.artist.isEmpty ? "YouTube" : track.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(duration(track.seconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(AppTheme.secondaryText)
                                    if let url = URL(string: track.url) {
                                        Link(destination: url) {
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Open \(track.title) on YouTube")
                                    }
                                }
                                .padding(10)
                                .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { store.refreshListeningHistory() }
        .onReceive(refreshTimer) { _ in store.refreshListeningHistory() }
        .confirmationDialog("Clear all listening history?", isPresented: $isClearConfirmationPresented) {
            Button("Clear Listening History", role: .destructive) {
                store.clearListeningHistory()
            }
        }
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
