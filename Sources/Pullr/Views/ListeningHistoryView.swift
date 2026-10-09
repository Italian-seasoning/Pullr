import Combine
import Charts
import SwiftUI

struct ListeningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isClearConfirmationPresented = false
    @State private var selectedWeek = Date()
    @State private var expandedSites: Set<String> = []
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let snapshot = insights
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Recording continues with Pullr closed. Manage allowed sites in the browser extension.", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.vertical, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                            ListeningMetric(title: "All recorded time", value: duration(snapshot.lifetimeSeconds), icon: "clock")
                            ListeningMetric(title: isCurrentWeek ? "This week" : "Selected week", value: duration(snapshot.week.totalSeconds), icon: "calendar")
                            ListeningMetric(title: "Websites in selected week", value: String(snapshot.week.sites.count), icon: "globe")
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
                            Button("Clear history…", role: .destructive) {
                                isClearConfirmationPresented = true
                            }
                        }
                        .padding(12)
                        .glassPanel(cornerRadius: 14, material: .ultraThinMaterial)

                        PlaybackWeekChart(days: snapshot.week.days, duration: duration)

                        if snapshot.week.sites.isEmpty {
                            ContentUnavailableView {
                                Label("No recorded time this week", systemImage: "clock")
                            } description: {
                                Text("In the Pullr extension, open Time tracking, add a website, and enable recording. The native helper saves time even when this app is quit.")
                            }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            Text("Websites")
                                .font(.headline)
                            LazyVStack(spacing: 8) {
                                ForEach(snapshot.week.sites) { site in
                                    DisclosureGroup(isExpanded: expansionBinding(for: site.id)) {
                                        VStack(spacing: 8) {
                                            ForEach(site.videos) { video in
                                                HStack(spacing: 10) {
                                                    Image(systemName: site.site == "youtube.com" ? "play.fill" : "globe")
                                                        .font(.caption)
                                                        .foregroundStyle(AppTheme.accent)
                                                    Text(video.title)
                                                        .lineLimit(2)
                                                    Spacer()
                                                    Text("\(video.sessionCount) \(video.sessionCount == 1 ? "session" : "sessions")")
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
                                        .accessibilityLabel("\(site.site), \(duration(site.seconds)), \(site.videos.count) entries")
                                    }
                                    .padding(12)
                                    .glassPanel(cornerRadius: 12, material: .thinMaterial)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
        if seconds <= 0 { return "0 min" }
        if seconds < 60 { return "\(Int(seconds)) sec" }
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
                    .font(.system(size: 28, weight: .medium).monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .glassPanel(cornerRadius: 14, material: .ultraThinMaterial)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaybackWeekChart: View {
    var days: [PlaybackDay]
    var duration: (Double) -> String
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily active time").font(.callout.weight(.semibold))
                Spacer()
                if let selectedDay {
                    Text("\(selectedDay.date.formatted(.dateTime.weekday(.abbreviated))): \(duration(selectedDay.seconds))")
                        .font(.caption.monospacedDigit())
                } else {
                    Text("Select a day for details").font(.caption)
                }
            }
            .foregroundStyle(AppTheme.secondaryText)
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.seconds / 60))
                        .cornerRadius(3)
                        .foregroundStyle(AppTheme.accent.opacity(selectedDay == nil || selectedDay?.id == day.id ? 0.9 : 0.35))
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                        .accessibilityValue(duration(day.seconds))
                }
                if let selectedDay {
                    RuleMark(x: .value("Selected day", selectedDay.date, unit: .day))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYScale(domain: 0...max(30, maxSeconds / 60))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppTheme.panelStroke)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(duration(minutes * 60)) }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .glassPanel(cornerRadius: 14, material: .ultraThinMaterial)
    }

    private var selectedDay: PlaybackDay? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var maxSeconds: Double {
        max(days.map(\.seconds).max() ?? 0, 1)
    }
}
