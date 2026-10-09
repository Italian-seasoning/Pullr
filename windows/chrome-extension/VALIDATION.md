# Pullr Chrome-only validation — 2026-10-08

## Passed

- Distribution update (0.3.0): title/quality appear before download; the filename field uses the full width; completion shows Saved and Download again; only confirmed HLS child playlists are grouped. The Chrome workflow exercised the queue waiting without writing, cancellation handing off to the next job, and clipboard URL validation. Node checks also covered queue ordering, duplicate joins, sender validation, tab close/reload cleanup, and unrelated-stream preservation.
- Dark UI update (0.2.2): dark mode stays active with a light system theme; the compact popup retains readable button targets; the vertical progress rail reaches 100% on completion and resets on cancellation. The full Chrome workflow passed again and both updated screenshots were inspected.
- Compact UI update (0.2.1): the four-stream popup fits in 320 × 328 pixels, buttons retain at least 32-pixel click targets, and the full Chrome download/login/cancellation workflow passed again. Updated popup and download-tab screenshots were inspected.
- Parser and validation checks: HTTP/HTTPS URL boundaries, credential-URL rejection, intact signed queries, relative paths, quality ranking, quoted attributes, explicit/implicit byte ranges, AES IVs, and clear rejection of live, protected, discontinuous, or truncated playlists.
- Existing Pullr stream/page capture checks and background checks for simultaneous captures, refreshed tokens, retained header context, no passive cookie storage, and navigation/close cleanup.
- Real downloads through the new JavaScript engine: MPEG-TS HLS to MP4, fragmented-MP4 HLS with byte ranges, AES-128 HLS, and direct MP4. FFprobe found H.264 video and AAC audio in each output, with approximately the expected four-second duration.
- Real Chrome for Testing 151 on macOS: captured a playing video in a cross-origin frame, an extensionless HLS master, DASH, and direct media; the popup opened the selected video's download tab.
- The actual download-tab controller, temporary Chrome header rules, network fetches, muxer, and browser file-stream writes produced a playable HLS output after the popup closed.
- A protected local fixture rejected the default anonymous request and succeeded only after login-session opt-in. It required the correct Cookie, Referer, Origin, and User-Agent; all were exercised through Chrome rather than a native application.
- Mid-download cancellation aborted the browser file stream and preserved the prior contents of an existing target file.
- Broken fragments failed without committing a successful output. Temporary Chrome request-header rules were absent after the browser tests.
- No browser page errors occurred during the tested workflow. Popup and download-tab screenshots were inspected visually.
- The extension has no nativeMessaging permission, remote executable code, bundled executable, account check, quota counter, paid gate, or artificial wait timer. Brief delays only accompany transient network retries.

## Test limits

Automation replaced the native Save As dialog with an origin-private browser file handle and OS clipboard reads with fixture text. Real browser file-stream reads/writes, commit, and abort were exercised, but the native save dialog and OS clipboard permission flow were not clicked through.

The browser run was on macOS. Windows/Linux Chrome and live commercial websites were not exercised. Long/large real-world videos were not measured; incremental writing was tested with short fixtures. Google Web Store review/publication has not happened.

DASH, separate audio-track merging, live recording, discontinuity handling, DRM, and website extractors are outside this first version. Unsupported streams are labeled or return a specific error; full limits are in the README.
