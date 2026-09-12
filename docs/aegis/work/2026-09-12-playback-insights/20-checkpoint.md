# Playback Insights Checkpoint

- Current todo: Task 3 pure weekly aggregation.
- Active slice: derive lifetime, calendar-week, daily, comparison, site, video, and session summaries.
- Completed: approved design, executable plan, browser playback gating, and compatible video identity persistence.
- Evidence: native-host checks passed; all 36 Swift tests passed; old JSONL decoding and sanitized anime/YouTube URLs are covered.
- Blockers: none.
- Next: write failing deterministic aggregation tests.
- Resume hint: read the plan, this checkpoint, and `10-intent.md`; compare worktree to the last evidence entry.
- Drift check: the existing `trackWebsite` and JSONL owners remain canonical; the change is additive and old rows decode; decision `continue`.
