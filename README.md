# Pullr

Pullr is a native macOS download queue for media you own, have permission to save, or can legally access offline. It supports individual links, playlists, direct HLS streams, audio import into Apple Music, and an optional Chrome extension.

## Requirements

- macOS 14 or newer
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)
- [`ffmpeg`](https://ffmpeg.org/)

Install the command-line dependencies with Homebrew:

```sh
brew install yt-dlp ffmpeg
```

## Install

Download the latest ZIP from [Releases](https://github.com/Italian-seasoning/Pullr/releases), move Pullr to Applications, then Control-click and choose **Open** the first time. Current preview builds are Sparkle-signed but not Apple-notarized.

## Chrome extension

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select `chrome-extension` from this repository.
3. Run `./native-host/install.sh` from Terminal.
4. Reload the extension after updating its files.

The extension can send supported pages to Pullr, match YouTube tracks in Apple Music, and keep a local listening-time history.

## Build and test

```sh
./script/run_unit_tests.sh
python3 native-host/test_native_host.py
node chrome-extension/test_music_tracker.js
node chrome-extension/test_page_capture.js
node chrome-extension/test_stream_capture.js
./script/build_and_run.sh --verify
```

Sparkle is pinned through Swift Package Manager. Release archives and appcasts are signed with a private key stored in the maintainer's macOS Keychain; the private key is never stored in this repository.

## Privacy and diagnostics

Pullr has no analytics or accounts. Settings, queue state, listening history, and diagnostics remain in `~/Library/Application Support/Pullr`. Diagnostic logs remove URL query strings and replace the home-directory prefix before writing. The Chrome native host records only timestamps, action names, outcomes, and safe error types.

Network access is limited to the links you request, Apple catalog matching, dependency updates you initiate, and GitHub Releases for Sparkle update checks.

Pullr does not decrypt DRM, bypass access controls, or automatically copy browser cookies. You are responsible for complying with site terms and applicable law.
