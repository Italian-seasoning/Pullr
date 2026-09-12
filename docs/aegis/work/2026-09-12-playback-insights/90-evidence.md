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

## Task 3 — Weekly aggregation

- Evidence action: full manual Swift suite and `git diff --check`.
- Result: exit 0; all 38 Swift tests passed.
- Covered scope: lifetime, weekly totals, seven daily buckets, full-prior-week comparison, zero baseline, grouping, sessions, and DST boundaries.
- Uncovered scope: visual rendering of derived values.
- Residual risk: UI wiring remains Task 4.
- Confidence: A.
