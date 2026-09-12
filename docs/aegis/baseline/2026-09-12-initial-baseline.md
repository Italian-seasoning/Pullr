# Initial Baseline — 2026-09-12

- Pullr is a native macOS 14 SwiftUI downloader with a Manifest V3 browser extension and Python native-messaging host.
- Optional activity is stored locally in `website-activity.jsonl`.
- Current website timing counts focused-tab time on a 30-second alarm and is not gated on video playback.
- Existing events contain site, title, seconds, timestamp, and YouTube classification but omit the page URL for non-YouTube sites.
- The Activity view shows simple totals and site rows without week navigation or a chart.
- Approved change authority: `docs/superpowers/specs/2026-09-12-playback-insights-design.md`.
