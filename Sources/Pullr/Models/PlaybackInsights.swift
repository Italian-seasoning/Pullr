import Foundation

enum PlaybackComparison: Equatable {
    case unchanged
    case new
    case percentage(Int)
}

struct PlaybackDay: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var seconds: Double
}

struct PlaybackVideoSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var seconds: Double
    var sessionCount: Int
}

struct PlaybackSiteSummary: Identifiable, Equatable {
    var id: String { site }
    var site: String
    var seconds: Double
    var videos: [PlaybackVideoSummary]
}

struct PlaybackWeekSummary: Equatable {
    var interval: DateInterval
    var totalSeconds: Double
    var comparison: PlaybackComparison
    var days: [PlaybackDay]
    var sites: [PlaybackSiteSummary]
}

struct PlaybackInsights: Equatable {
    var lifetimeSeconds: Double
    var week: PlaybackWeekSummary

    init(events: [WebsiteActivityEvent], selectedDate: Date, calendar: Calendar = .current) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: calendar.startOfDay(for: selectedDate), duration: 7 * 86_400)
        let current = events.filter { interval.contains($0.date) }
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: interval.start) ?? interval.start
        let previous = events.filter { $0.date >= previousStart && $0.date < interval.start }
        let currentTotal = current.reduce(0) { $0 + $1.seconds }
        let previousTotal = previous.reduce(0) { $0 + $1.seconds }

        lifetimeSeconds = events.reduce(0) { $0 + $1.seconds }
        week = PlaybackWeekSummary(
            interval: interval,
            totalSeconds: currentTotal,
            comparison: Self.comparison(current: currentTotal, previous: previousTotal),
            days: (0..<7).compactMap { offset in
                guard let start = calendar.date(byAdding: .day, value: offset, to: interval.start),
                      let end = calendar.date(byAdding: .day, value: 1, to: start)
                else { return nil }
                return PlaybackDay(date: start, seconds: current.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.seconds })
            },
            sites: Self.siteSummaries(current)
        )
    }

    private static func comparison(current: Double, previous: Double) -> PlaybackComparison {
        guard previous > 0 else { return current > 0 ? .new : .unchanged }
        return .percentage(Int((((current - previous) / previous) * 100).rounded()))
    }

    private static func siteSummaries(_ events: [WebsiteActivityEvent]) -> [PlaybackSiteSummary] {
        Dictionary(grouping: events, by: \.site).map { site, siteEvents in
            let groupedVideos: [String: [WebsiteActivityEvent]] = Dictionary(grouping: siteEvents) { event in
                if let url = event.url, !url.isEmpty { return url }
                return event.site + "|" + event.title
            }
            var videos: [PlaybackVideoSummary] = []
            for (key, videoEvents) in groupedVideos {
                videos.append(videoSummary(key: key, events: videoEvents, fallbackTitle: site))
            }
            videos.sort { left, right in
                left.seconds == right.seconds ? left.title < right.title : left.seconds > right.seconds
            }
            return PlaybackSiteSummary(
                site: site,
                seconds: siteEvents.reduce(0) { $0 + $1.seconds },
                videos: videos
            )
        }.sorted { $0.seconds == $1.seconds ? $0.site < $1.site : $0.seconds > $1.seconds }
    }

    private static func videoSummary(key: String, events: [WebsiteActivityEvent], fallbackTitle: String) -> PlaybackVideoSummary {
        let ordered = events.sorted { $0.recordedAt < $1.recordedAt }
        let title = ordered.reversed().first { !$0.title.isEmpty }?.title ?? fallbackTitle
        var sessions = 0
        var previousTimestamp: Double?
        for event in ordered {
            if let previousTimestamp {
                let gap: Double = event.recordedAt - previousTimestamp
                if gap > 90 { sessions += 1 }
            } else {
                sessions = 1
            }
            previousTimestamp = event.recordedAt
        }
        return PlaybackVideoSummary(
            id: key,
            title: title,
            seconds: ordered.reduce(0) { $0 + $1.seconds },
            sessionCount: sessions
        )
    }
}
