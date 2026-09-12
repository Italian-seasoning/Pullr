# Playback Insights Design

## Goal

Make Pullr's optional, local activity view accurately report video watch time from Chrome and Comet. The view will provide lifetime totals, navigable weekly summaries, week-over-week comparison, a seven-day chart, and website groups that expand into watched-video details.

Pullr remains a downloader with simple insights. This work does not add accounts, cloud sync, recommendations, social features, or general screen-time tracking.

## Tracking Semantics

Pullr counts time only when all of these conditions hold:

- an HTML video is actively playing;
- its document is visible;
- its browser window is focused;
- the system is not idle; and
- activity tracking is enabled.

Pausing, ending playback, hiding the tab, changing tabs, blurring the browser window, becoming idle, disabling tracking, or closing the document ends the active segment. Muted playback still counts because it is still intentional playback. Seeking does not add the skipped interval.

The tracker will use bounded heartbeats so a crashed browser or missing stop message cannot create unbounded time. Native persistence will continue rejecting non-positive or implausibly long segments.

## Browser Capture

The Manifest V3 extension will add one focused playback observer shared by Chrome and Comet. It will observe media elements in the top document and eligible frames, report play-state transitions, and handle single-page navigation such as YouTube changing videos without a full reload.

The background worker remains responsible for focus, active-tab, idle, enablement, and native-messaging checks. It will combine these signals with playback state and send completed segments through the existing native host. This replaces focused-tab website timing for video activity and prevents generic tab time from double-counting playback.

Chrome and Comet will use the same event format and application-support store. Browser identity will not appear in the model or interface, so their time is combined by default. Installation or native-host registration may differ by browser; both paths must be exercised before compatibility is claimed.

## Event Data

Each persisted playback segment contains:

- normalized website host;
- canonical page or video URL;
- page or video title;
- elapsed playback seconds; and
- the timestamp at which the segment was recorded.

The current JSON-lines activity file remains the storage boundary. New decoding must remain compatible with existing events. Existing focused-tab records stay visible as historical data; only new records use playback-only semantics. No destructive migration is required.

Video details are grouped by normalized URL within a website. The most recent non-empty title becomes the display title. Each group reports total duration and the number of distinct playback sessions. Adjacent segments for the same URL separated only by normal heartbeat boundaries count as one session.

## Aggregation

A small pure Swift aggregation layer will derive display models from stored events:

- lifetime playback duration across all valid events;
- selected calendar-week duration;
- seven daily totals for the selected week;
- percentage change from the complete preceding calendar week;
- website totals for the selected week; and
- video totals and session counts within each website.

Week boundaries follow the user's system calendar and time zone. Previous and next controls move by whole calendar weeks. The next control is disabled for the current week, and a `This Week` action returns to it.

The comparison always uses the selected week's accumulated total against all seven days of the previous week, including when the selected week is still in progress. If the previous week is zero and the selected week is positive, the interface shows `New`. If both are zero, it shows no change rather than a percentage.

## Activity Interface

The existing Activity section keeps Pullr's current navigation and visual system. Its content becomes:

1. A compact lifetime watch-time metric.
2. A weekly header with previous/next arrows, the selected date range, and `This Week` when viewing history.
3. The selected week's watch time and prior-week change indicator.
4. A simple seven-bar chart labeled by weekday, with accessible text values for every bar.
5. Website disclosure rows, sorted by selected-week duration and collapsed by default.

Each website row shows its display name and total duration. Expanding it reveals watched videos sorted by duration, with title, duration, and session count. Raw URLs are fallback labels only when no title exists. Empty weeks show an informative empty state while the lifetime total remains available.

The existing clear-history action continues to clear all locally stored activity after its current confirmation flow.

## Failure Handling and Privacy

Tracking remains opt-in and local. The extension sends no activity to Pullr's developer or a third-party analytics service. Query strings used only for authentication or volatile playback state must not be persisted. The implementation will not decrypt DRM, copy browser cookies, or bypass access controls.

Unsupported cross-origin or protected players should fail closed: Pullr records no time rather than estimating it. Native-message failures retain the existing safe diagnostic behavior without logging full sensitive URLs.

## Verification

Automated tests will cover:

- play, pause, end, visibility, focus, idle, and enablement transitions;
- heartbeat bounds and prevention of double counting;
- YouTube single-page navigation and normalized video identity;
- calendar-week boundaries and daylight-saving transitions;
- lifetime and daily totals;
- full-previous-week percentage comparison and zero baselines;
- website and video grouping; and
- session coalescing.

The project will be built and tested through its existing Xcode-compatible scripts. Manual smoke tests will play, pause, switch tabs, and change videos on YouTube and at least one ordinary HTML5 anime player in both Chrome and Comet. A successful build alone will not be treated as browser-runtime verification.

