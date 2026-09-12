# Playback Insights Implementation Plan

## Goal

Implement the approved playback-only tracker and local lifetime/weekly insights in Chrome and Comet while preserving existing activity history.

## Architecture

Reuse `page-capture.js` and `content-bridge.js` to report per-frame playback state. Keep `background.js` as the canonical focus/idle/active-tab timer and gate its existing segments on playback state. Extend the existing native event contract with a sanitized canonical URL. Add a pure Swift `PlaybackInsights` aggregation model and render it from the existing Activity view.

## Tech Stack

Manifest V3 JavaScript, Python 3 native messaging, Swift 5.9, SwiftUI on macOS 14, Foundation `Calendar`, the existing shell/Node/Python test runners, and SwiftPM/Xcode-compatible builds.

## Baseline/Authority Refs

- `docs/superpowers/specs/2026-09-12-playback-insights-design.md`
- `docs/aegis/baseline/2026-09-12-initial-baseline.md`
- `PRODUCT.md`, `DESIGN.md`, and the current source tree

## Compatibility Boundary

Old JSONL rows must continue decoding. The native host action remains `trackWebsite`. Chrome and Comet share one application-support file and no browser dimension. Activity remains opt-in and local. Unsupported players fail closed. Existing downloads, stream capture, and YouTube Music matching remain unchanged.

## TDD Route

- Mode: auto
- Decision: strict
- Strict authority: recorded auto decision
- Strict signals: behavioral bug fix, JS/Python/Swift producer-consumer contract, persistence compatibility, date aggregation
- Light eligibility: none
- TDD-fit exception: browser runtime still needs manual smoke testing
- Test posture: strict RED test
- Reason: the change crosses three runtimes and old persisted data must remain readable
- Verification: focused Node, Python, Swift, full unit, build, then Chrome and Comet smoke checks

## Scope and Readiness

**Aegis Visibility:** Planning is useful because playback state crosses a browser/native persistence contract and must remain backwards compatible.

**BaselineUsageDraft:** Required, acknowledged, and cited refs are the approved design, current source, and initial baseline. Missing refs: none. Decision: continue.

**Requirement Ready Check:** Lifetime data, week navigation, seven-day chart, full-prior-week comparison, collapsed websites, expanded video detail, combined browsers, and playback-only semantics are approved. Open blocker questions: none. Decision: ready.

**Change Necessity:** Configuration cannot distinguish playback from a focused tab or render weekly aggregation. Minimum code boundary is the existing extension capture/background path, native event sanitizer, one Swift aggregation model, the Activity view, and their tests. Decision: code-change.

**Existence Check:** Reuse the page-capture bridge, background timer, native host, JSONL store, Activity section, and manual Swift test runner. Only `PlaybackInsights.swift` is new because date aggregation does not belong in the SwiftUI view or persistence store. Decision: add-with-proof.

**Architecture Integrity Lens:** `background.js` remains the single authority for active/focused/idle timing; the page script reports playback state only. `PlaybackInsights` owns pure presentation aggregation. No parallel timer or store is introduced. Verdict: proceed.

**Plan Pressure Test:** Owners and contracts are explicit, old records remain readable, commands are known, and runtime browser claims are held behind manual proof. Pressure result: proceed.

**Complexity Budget:** `background.js` and `ListeningHistoryView.swift` are moderate files. Playback gating stays in the existing background flow; aggregation is extracted from the view. Budget result: within-budget.

## Files

- Modify `chrome-extension/page-capture.js`: emit playback-state transitions from media events.
- Modify `chrome-extension/content-bridge.js`: validate and relay playback state.
- Modify `chrome-extension/website-tracker.js`: make activity creation explicitly playback-gated and keep bounded segments.
- Modify `chrome-extension/background.js`: persist per-frame playback state, gate timing, and clear stale state.
- Modify `chrome-extension/test_page_capture.js` and `chrome-extension/test_website_tracker.js`: cover playback transitions and gating.
- Modify `native-host/pullr_native_host.py` and `native-host/test_native_host.py`: sanitize and persist canonical video URLs for every site.
- Modify `Sources/Pullr/Models/WebsiteActivityEvent.swift`: add optional `url` for backwards-compatible decoding.
- Create `Sources/Pullr/Models/PlaybackInsights.swift`: pure weekly/lifetime/site/video aggregation.
- Modify `Sources/Pullr/Views/ListeningHistoryView.swift`: week navigation, comparison, chart, and disclosure rows.
- Modify `Tests/PullrUnitTests/main.swift` and `script/run_unit_tests.sh`: aggregation, decoding, and grouping tests.
- Modify `native-host/install.sh` only if Comet requires a separate manifest registration path confirmed on this machine.

## Task 1: Playback-Gate Browser Segments

**Why:** Focused-tab time is the root cause of inaccurate YouTube totals and cannot detect anime playback.

**Change Necessity:** Browser code must expose actual HTML video state. Reuse the current bridge and timer; do not add a second heartbeat.

**Impact/Compatibility:** Stream capture messages remain unchanged. Per-frame state prevents one paused iframe from masking another playing iframe.

**Steps:**

1. Add failing assertions to `test_page_capture.js` for `playing`, `waiting`, `pause`, `ended`, and `seeking` messages; run `rtk node chrome-extension/test_page_capture.js` and confirm RED.
2. In `page-capture.js`, capture media events and post `{source: "pullr-playback", playing: Bool}` only when aggregate state changes; run the focused test GREEN.
3. Add failing pure-function assertions to `test_website_tracker.js` showing `activityForTab(tab, false)` is nil and `activityForTab(tab, true)` preserves the top-page URL/title; confirm RED.
4. Update `website-tracker.js` with the playback argument and run GREEN.
5. Update `content-bridge.js` to relay only boolean playback messages as `videoPlaybackState` while preserving existing stream validation.
6. Update `background.js` with `playback:<tabId>` session state keyed by `sender.frameId`; refresh the existing activity segment after every transition, require an active playing frame before starting the next segment, and clear the key on tab navigation/removal.
7. Run `rtk node chrome-extension/test_page_capture.js`, `rtk node chrome-extension/test_website_tracker.js`, and every existing `chrome-extension/test_*.js` file.
8. Commit the verified browser slice.

## Task 2: Preserve Video Identity Through Native Storage

**Why:** Expanded website rows need stable per-video identity and titles for non-YouTube sites.

**Change Necessity:** The current native host deliberately drops non-YouTube titles and all URLs, so UI-only grouping is impossible.

**Impact/Compatibility:** Additive `url` field only; old rows decode because Swift uses an optional property. Strip fragments and volatile/authentication query keys. Keep YouTube's `v` identity.

**Steps:**

1. Add failing native-host assertions for anime title/URL persistence, volatile query removal, YouTube canonicalization, and invalid URL rejection; run `rtk python3 native-host/test_native_host.py` and confirm RED.
2. Add one `_canonical_activity_url` helper in `pullr_native_host.py`, preserve safe titles for every host, and include `url` in the event; run the Python test GREEN.
3. Add optional `url: String?` to `WebsiteActivityEvent`.
4. Add `WebsiteActivityEvent.swift` and `WebsiteActivityStore.swift` to `script/run_unit_tests.sh`; add a failing Swift test that decodes an old row without `url` and a new row with it, then run `rtk script/run_unit_tests.sh` to confirm RED/GREEN around the model change.
5. Commit the verified persistence slice.

## Task 3: Build Pure Weekly Aggregation

**Why:** Lifetime, week navigation, comparison, chart, sites, videos, and sessions need one testable source of truth.

**Change Necessity:** These derived values do not exist. They belong outside SwiftUI and persistence.

**Impact/Compatibility:** Read-only derivation from existing events. Calendar/time zone are injected for deterministic tests. Adjacent same-video segments with gaps no larger than the 90-second persistence bound form one session.

**Steps:**

1. Add `PlaybackInsights.swift` to `script/run_unit_tests.sh` and failing tests covering week bounds, DST, lifetime, daily totals, full-prior-week percentage, zero baselines, website/video grouping, and session coalescing; run the Swift runner and confirm RED.
2. Create value types `PlaybackInsights`, `PlaybackWeekSummary`, `PlaybackSiteSummary`, `PlaybackVideoSummary`, and `PlaybackComparison` with one initializer accepting events, selected date, and calendar.
3. Implement aggregation using `Calendar.dateInterval(of: .weekOfYear, for:)`, daily buckets, normalized URL fallback, and sorted summaries.
4. Run the focused Swift runner GREEN and commit the aggregation slice.

## Task 4: Render the Activity Dashboard

**Why:** Users need the approved lifetime and navigable weekly insights.

**Change Necessity:** The existing view has only fixed totals and flat site rows.

**Impact/Compatibility:** Keep the Activity navigation section, theme components, refresh timer, clear-history confirmation, and listening history below the website insights only where it does not double-count playback totals.

**Legacy compatibility addendum:** Runtime inspection found that existing accurate YouTube playback history lives in `listening-history.jsonl`, while `website-activity.jsonl` may be absent or contain the older focused-tab estimates. Before UI closeout, import legacy listening events into the aggregation boundary, prefer them over old URL-less YouTube website events, and stop producing new `trackListening` rows once canonical playback events exist. This preserves lifetime history without ongoing double counting.

**Steps:**

1. Add a failing Swift regression proving legacy `ListeningEvent` rows populate lifetime/week/video summaries while old URL-less YouTube website estimates do not double count; confirm RED.
2. Extend `PlaybackInsights` with an optional legacy-listening input and implement the compatibility merge; change `background.js` to acknowledge but no longer persist `trackListening`; run Swift and extension regressions GREEN.
3. Add `@State` for the selected week and expanded-site IDs to `ListeningHistoryView.swift`.
4. Replace fixed website metrics with lifetime total, selected-week total, comparison badge, previous/next/This Week controls, and a seven-bar SwiftUI chart built from layout primitives so no dependency is added.
5. Replace flat rows with collapsed `DisclosureGroup` website rows whose children show grouped title, duration, and session count.
6. Add accessibility labels/values to navigation controls, comparison, chart bars, and disclosure rows.
7. Build with `rtk xcodebuild -scheme Pullr -destination 'platform=macOS' build` and package with `rtk proxy bash script/build_and_run.sh --verify`.
8. Launch the exact rebuilt bundle, confirm its executable timestamp/path, and verify empty, current-week, historical-week, and expanded-site states without altering the user's real activity file.
9. Commit the verified compatibility/UI slice.

## Task 5: Cross-Browser Runtime Verification

**Why:** A build cannot prove browser focus, iframe playback, native messaging, or Comet registration.

**Change Necessity:** Runtime verification is necessary; source changes are conditional on confirmed Comet manifest-path differences.

**Impact/Compatibility:** Use throwaway activity data or back up and restore the exact activity file. Do not claim unsupported protected players.

**Steps:**

1. Run the full automated suite: `rtk script/run_unit_tests.sh`, all Node extension tests, and `rtk python3 native-host/test_native_host.py`.
2. Install/reload the same unpacked extension in Chrome and Comet and confirm native messaging reaches Pullr in each.
3. In each browser, play and pause a YouTube video, switch tabs, unfocus the window, and play one ordinary HTML5 anime episode page; verify only played, focused intervals appear.
4. Verify both browsers' events combine in lifetime and weekly totals, week arrows work, the current-week next arrow is disabled, full-prior-week comparison is correct, and sites start collapsed.
5. If Comet requires a separate native-host manifest location, make only that installer change, add an installer assertion, reinstall, and repeat its smoke test.
6. Run `rtk git diff --check`, inspect `rtk git status --short`, and commit the final verified slice.

## Risks and Retirement

- Cross-origin protected players may not expose usable media events; fail closed and report the verified boundary.
- Old focused-tab events remain in lifetime history and are labeled only by their stored metadata; no destructive migration.
- Query sanitization can merge URLs too aggressively; preserve stable identifiers such as YouTube `v` while removing volatile secrets.
- The old unconditional focused-tab behavior is retired when playback gating lands. No fallback timer remains.
- Rollback is per coherent commit: browser gating, persistence contract, aggregation, UI, and conditional Comet installer.

## Execution Readiness View

- Intent Lock: playback-only, local, simple insights
- Scope Fence: no accounts, sync, recommendations, general screen time, or chart dependency
- Baseline Lock: approved design plus current Pullr source and initial baseline
- Approved Behavior: lifetime, weekly navigation, seven bars, full-prior-week comparison, collapsed sites, expanded videos, combined browsers
- Owner / Contract Constraints: background owns timing; native host sanitizes; Swift aggregator derives; view renders
- Compatibility Boundary: old JSONL and existing extension features survive
- Retirement Boundary: remove unconditional focused-tab counting, retain no hidden fallback
- Task Batches: browser, persistence, aggregation, UI, runtime proof
- Test Obligations: Node, Python, Swift, build, Chrome, Comet
- Review Gates: after each coherent task and before runtime claims
- Drift / Rewind Rules: return to design if the native event schema needs a destructive migration or Comet needs a different extension architecture
- Evidence Required Before Completion: passing automated suite, successful build, and clearly separated Chrome/Comet manual results
- Advisory Boundary: method-pack execution guidance only; not completion authority

## Execution Route

- Decision: inline
- Evidence: shared files and sequential producer-consumer changes outweigh delegation benefit; subagents were not requested
- Fallback: stop at the last verified commit if a browser-runtime boundary needs user action
- User confirmation required: no
