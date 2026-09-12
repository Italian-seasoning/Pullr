import Combine
import SwiftUI

struct ListeningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isClearConfirmationPresented = false
    @State private var selectedWeek = Date()
    @State private var expandedSites: Set<String> = []
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.websiteActivity.isEmpty && store.listeningHistory.isEmpty {
                ContentUnavailableView {
                    Label("No activity yet", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("Enable hours tracking in the Pullr extension to begin.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            ListeningMetric(title: "Lifetime", value: duration(insights.lifetimeSeconds), icon: "infinity")
                            ListeningMetric(title: "Selected week", value: duration(insights.week.totalSeconds), icon: "calendar")
                        }

                        HStack {
                            Button { moveWeek(-1) } label: {
                                Image(systemName: "chevron.left")
                            }
                            .accessibilityLabel("Previous week")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(weekLabel)
                                    .font(.headline)
                                Text(comparisonLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(comparisonColor)
                                    .accessibilityLabel("Usage compared with previous week: \(comparisonLabel)")
                            }
                            Button { moveWeek(1) } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(isCurrentWeek)
                            .accessibilityLabel("Next week")
                            Spacer()
                            if !isCurrentWeek {
                                Button("This Week") { selectedWeek = Date() }
                            }
                            Button("Clear", role: .destructive) {
                                isClearConfirmationPresented = true
                            }
                        }

                        PlaybackWeekChart(days: insights.week.days, duration: duration)

                        if insights.week.sites.isEmpty {
                            ContentUnavailableView("No playback this week", systemImage: "play.slash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            Text("Websites")
                                .font(.headline)
                            LazyVStack(spacing: 8) {
                                ForEach(insights.week.sites) { site in
                                    DisclosureGroup(isExpanded: expansionBinding(for: site.id)) {
                                        VStack(spacing: 8) {
                                            ForEach(site.videos) { video in
                                                HStack(spacing: 10) {
                                                    Image(systemName: "play.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(AppTheme.accent)
                                                    Text(video.title)
                                                        .lineLimit(2)
                                                    Spacer()
                                                    Text("\(video.sessionCount) \(video.sessionCount == 1 ? "play" : "plays")")
                                                        .font(.caption)
                                                        .foregroundStyle(AppTheme.tertiaryText)
                                                    Text(duration(video.seconds))
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(AppTheme.secondaryText)
                                                }
                                            }
                                        }
                                        .padding(.top, 8)
                                    } label: {
                                        HStack {
                                            Image(systemName: site.site == "youtube.com" ? "play.rectangle.fill" : "globe")
                                                .foregroundStyle(AppTheme.accent)
                                                .frame(width: 24)
                                            Text(site.site == "youtube.com" ? "YouTube" : site.site)
                                                .font(.callout.weight(.semibold))
                                            Spacer()
                                            Text(duration(site.seconds))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(AppTheme.secondaryText)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("\(site.site), \(duration(site.seconds)), \(site.videos.count) videos")
                                    }
                                    .padding(12)
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

    private var insights: PlaybackInsights {
        PlaybackInsights(events: store.websiteActivity, legacyListeningEvents: store.listeningHistory, selectedDate: selectedWeek)
    }

    private var isCurrentWeek: Bool {
        let calendar = Calendar.current
        guard let selected = calendar.dateInterval(of: .weekOfYear, for: selectedWeek),
              let current = calendar.dateInterval(of: .weekOfYear, for: Date())
        else { return true }
        return selected.start == current.start
    }

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: insights.week.interval.end) ?? insights.week.interval.end
        return insights.week.interval.start.formatted(.dateTime.month(.abbreviated).day())
            + " – " + end.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var comparisonLabel: String {
        switch insights.week.comparison {
        case .unchanged: "No change from previous week"
        case .new: "New from previous week"
        case .percentage(let value): value == 0 ? "No change from previous week" : "\(abs(value))% \(value > 0 ? "up" : "down") from previous week"
        }
    }

    private var comparisonColor: Color {
        if case .percentage(let value) = insights.week.comparison, value < 0 { return AppTheme.success }
        if case .percentage(let value) = insights.week.comparison, value > 0 { return AppTheme.warning }
        return AppTheme.secondaryText
    }

    private func moveWeek(_ offset: Int) {
        selectedWeek = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedWeek) ?? selectedWeek
    }

    private func expansionBinding(for site: String) -> Binding<Bool> {
        Binding(
            get: { expandedSites.contains(site) },
            set: { expanded in
                if expanded { expandedSites.insert(site) }
                else { expandedSites.remove(site) }
            }
        )
    }

    private func duration(_ seconds: Double) -> String {
        if seconds >= 3_600 { return String(format: "%.1f h", seconds / 3_600) }
        return "\(max(1, Int(seconds / 60))) min"
    }
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

private struct PlaybackWeekChart: View {
    var days: [PlaybackDay]
    var duration: (Double) -> String

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(day.seconds > 0 ? AppTheme.accent : AppTheme.panelStroke)
                        .frame(height: max(4, 92 * day.seconds / maxSeconds))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(duration(day.seconds))
            }
        }
        .frame(height: 120)
        .padding(12)
        .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var maxSeconds: Double {
        max(days.map(\.seconds).max() ?? 0, 1)
    }
}
