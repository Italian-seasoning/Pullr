<p align="center">
  <img src="docs/pullr-icon.png" width="144" alt="Pullr app icon">
</p>

<h1 align="center">Pullr</h1>

<p align="center">
  <a href="https://nolan-mac-apps.nolankrahn.chatgpt.site/apps/pullr">Software showcase</a> ·
  <a href="https://italian-seasoning.github.io/Pullr/">Website</a> ·
  <a href="https://github.com/Italian-seasoning/Pullr/releases/latest">Latest preview</a> ·
  <a href="PRIVACY.md">Privacy</a>
</p>

Pullr is a native macOS download queue for media you own, have permission to save, or can legally access offline. It supports individual links, playlists, direct HLS streams, audio import into Apple Music, and an optional Chrome extension.

## Quick install

```sh
brew install --cask italian-seasoning/tap/pullr
```

Install the media tools with `brew install yt-dlp ffmpeg deno`.

Current preview: **1.1.2**. [Download the DMG](https://github.com/Italian-seasoning/Pullr/releases/download/v1.1.2/Pullr-1.1.2-macOS.dmg).

Requires macOS 14 or newer on Apple silicon or Intel.

These previews are not Apple-notarized. Homebrew verifies the archive checksum and leaves Gatekeeper enabled. If macOS blocks the first launch, review the app in **System Settings → Privacy & Security**. Sparkle verifies subsequent in-app updates with its signed feed.

## See the app

![Pullr playlist workspace with season-capture entry point](docs/screenshots/pullr-playlists.png)

![Pullr export presets and format controls](docs/screenshots/pullr-presets.png)

![Pullr dependency status and update controls](docs/screenshots/pullr-dependencies.png)

[Watch the interface walkthrough](docs/screenshots/pullr-walkthrough.mp4). This short sequence shows the captured interface views; it is not a gameplay or download benchmark.

Screenshots show local preview builds. Empty queues and standby states are shown where applicable.


## Requirements

- macOS 14 or newer
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
- [`ffmpeg`](https://ffmpeg.org/)
- [`Deno`](https://deno.com/) for YouTube challenge handling

Install the command-line dependencies with Homebrew:

```sh
brew install yt-dlp ffmpeg deno
```

## Install

Download the latest DMG from [Releases](https://github.com/Italian-seasoning/Pullr/releases). It contains Pullr.app and an `Install Pullr.command` helper; double-click the helper for a one-step install. Current preview builds are Sparkle-signed but not Apple-notarized, so Control-click Pullr and choose **Open** the first time.

## Chrome extension

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select `chrome-extension` from this repository.
3. Run `./native-host/install.sh` from Terminal.
4. Reload the extension after updating its files.

The extension can send supported pages to Pullr and match YouTube tracks in Apple Music. Website and YouTube hours tracking is optional and off by default; enable it from the extension popup.

The popup separates **Capture media** and **Time tracking**, with labelled actions and a local sync status. Add an allowed website before enabling recording. The browser and native messaging helper record active time even when Pullr is quit; reopening Pullr reads the saved records. If the helper is unavailable, segments wait in local browser storage and retry automatically. Recording pauses at 2,000 pending segments until syncing recovers. Retries retain their original timestamps and avoid duplicate recent acknowledgements. Private/incognito tabs are excluded; non-YouTube records retain only the domain. Reload the unpacked extension after updating its files.

The native app uses flat charcoal panels and a time dashboard with recorded totals, website counts, and per-site detail. Its daily chart includes duration axes, weekday labels, and day selection for inspecting totals. Empty days display zero rather than a fabricated minute of activity.

## Build and test

```sh
./script/run_unit_tests.sh
./script/run_app_store_smoke.sh
python3 native-host/test_native_host.py
node chrome-extension/test_music_tracker.js
node chrome-extension/test_page_capture.js
node chrome-extension/test_stream_capture.js
node chrome-extension/test_popup.js
node chrome-extension/test_website_tracker.js
node chrome-extension/test_activity_outbox.js
node chrome-extension/test_background_activity.js
node chrome-extension/test_background_tracking.js
./script/build_and_run.sh --verify
```

For a compact local release, run `PULLR_CONFIGURATION=release ./script/build_and_run.sh --package`, then `python3 script/verify_local_build.py dist/Pullr.app`. Release builds optimize for size and include only this Mac's CPU architecture, including Sparkle's helpers. Set `PULLR_ARCHITECTURE=universal` to build for both Apple Silicon and Intel; the publication script does this automatically.

YouTube video presets finish as H.265 (HEVC) MP4 files using the Mac's VideoToolbox encoder, with AAC audio and the `hvc1` tag for macOS playback. Pullr downloads the selected source quality, then converts it before marking the item complete. Audio and Original presets preserve their existing behavior. Failed or cancelled conversion keeps the source file.

`./script/run_hevc_smoke.sh` checks actual encoding and failure preservation with generated fixtures. Set `PULLR_TEST_YOUTUBE_URL` to a short YouTube video to check the complete download and conversion path.

Sparkle is pinned through Swift Package Manager. Release archives and appcasts are signed with a private key stored in the maintainer's macOS Keychain; the private key is never stored in this repository.

## Privacy and diagnostics

Pullr has no analytics or accounts. The developer does not receive activity data. Settings, queue state, optional local activity history, and diagnostics remain in `~/Library/Application Support/Pullr`. Diagnostic logs remove URL query strings and replace the home-directory prefix before writing. The Chrome native host records only timestamps, action names, outcomes, and safe error types.

Network access is limited to the links you request, Apple catalog matching, dependency updates you initiate, and GitHub Releases for Sparkle update checks.

Pullr does not decrypt DRM, bypass access controls, or automatically copy browser cookies. You are responsible for complying with site terms and applicable law.

See [Privacy](PRIVACY.md) and [Terms of Use](TERMS.md).

## License and attribution

[MIT](LICENSE) — Copyright © 2026 [Italian-seasoning](https://github.com/Italian-seasoning). Forks and redistribution are allowed; retain the copyright and license notice. Please identify independently maintained forks and link back to this project. Third-party components retain their own licenses.
