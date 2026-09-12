# Playback Insights Evidence

## Task 1 — Browser playback gating

- Evidence action: all four existing Node suites, JavaScript syntax checks for background and content bridge, and `git diff --check`.
- Result: exit 0; page capture, website tracker, stream capture, and music tracker passed.
- Covered scope: media-state transitions, playback gating helper, syntax, and adjacent extension regressions.
- Uncovered scope: live Chrome/Comet focus, service-worker, iframe, and native-messaging behavior.
- Residual risk: manual browser proof remains Task 5.
- Confidence: B.

## Task 2 — Video identity persistence

- Evidence action: native-host suite, full manual Swift suite, and `git diff --check`.
- Result: exit 0; native host passed and all 36 Swift tests passed.
- Covered scope: URL sanitization, anime titles, YouTube canonicalization, old/new event decoding, and adjacent Swift regressions.
- Uncovered scope: existing real-world legacy rows with malformed optional data.
- Residual risk: bounded by lossy decoding already used by the store.
- Confidence: A.

## Task 4 — Legacy compatibility and Activity dashboard

- Evidence action: 39-test Swift suite, all extension suites, native-host suite, Xcode build, exact executable timestamp/path check, and direct accessibility/screenshot inspection.
- Result: exit 0; lifetime 17.2 h and weekly 4.4 h rendered, prior/next navigation changed the week and comparison, current next was disabled, and YouTube expanded from a collapsed row into video details.
- Covered scope: legacy lifetime preservation, no old focused-tab double count when legacy playback exists, dashboard layout, chart values, navigation, comparison, disclosure behavior, and accessibility values.
- Uncovered scope: live updated extension behavior inside Chrome and Comet.
- Residual risk: browsers must reload the unpacked extension before playback smoke testing.
- Confidence: A for app/UI, B for the combined producer-consumer slice.

### Debug closure

- Symptom: the exact new bundle initially showed no lifetime activity.
- Reproduction: `website-activity.jsonl` absent while `listening-history.jsonl` contains historical playback.
- Root: the legacy producer and new dashboard consumed separate stores; continued `trackListening` writes would regenerate missing or duplicated lifetime data.
- Repair: merge pre-cutover legacy listening events at `PlaybackInsights`, prefer them over URL-less YouTube estimates, and retire new `trackListening` persistence.
- Retirement: the action is acknowledged for extension compatibility but writes no new legacy rows.
- Falsifier: a stale app binary could mimic the symptom; exact path/timestamp rebuild then rendered legacy totals, excluding that alternative.
- Topology: chain at the producer-consumer contract; no platform-level store-access issue remained.

## Task 3 — Weekly aggregation

- Evidence action: full manual Swift suite and `git diff --check`.
- Result: exit 0; all 38 Swift tests passed.
- Covered scope: lifetime, weekly totals, seven daily buckets, full-prior-week comparison, zero baseline, grouping, sessions, and DST boundaries.
- Uncovered scope: visual rendering of derived values.
- Residual risk: UI wiring remains Task 4.
- Confidence: A.
