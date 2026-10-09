# Pullr — Chrome-only video downloader

This is a working first version of Pullr's own browser download engine. It requires no Windows application, native host, yt-dlp, FFmpeg, account, subscription, daily quota, or forced waiting period. It downloads locally and saves incrementally to disk instead of assembling an entire video in RAM.

The interface uses dark mode only, compact labeled controls, and a vertical download progress rail. Ready videos show their title, quality, and duration when available; completed downloads show Saved and Download again. Filenames have a full-width field.

## Install and use

1. Extract `PullrChrome.zip` to a permanent folder.
2. Open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and select the folder containing `manifest.json`.
3. Pin Pullr in Chrome's toolbar. Reload video pages that were open before installation.
4. Play the embedded video, open Pullr, and click **Refresh**.
5. Click **Download** beside the stream. A Chrome download tab opens. Choose a quality if offered, then click **Download** to choose a save location.
6. Keep that download tab open until it says **Saved**. The extension popup can close. **Cancel** aborts the incomplete save.

Use **Paste link** to read a copied direct-file or M3U8 URL from the clipboard. Clipboard access happens only when you click this button. **Copy link** copies the selected media URL. **Check video** rechecks a pasted or changed link. If a site requires your login, select **Use site login**, then click **Check video** again. Login use is off by default.

Choose a save location for each video to add it to the queue. Downloads run one at a time; queued jobs leave existing files untouched until their turn. The popup lists active and queued downloads with an **Open** button. **Cancel** or closing a job's tab releases its place in the queue. Keep every queued tab open. Jobs do not resume after Chrome closes.

HLS quality playlists are grouped under their master only when the captured master explicitly identifies them. Other streams remain separate. Titles use the source page title; formats are secondary.

This folder is also the extension source. Chrome desktop 125 or newer is required; the same extension is intended for Chrome on Windows, macOS, and Linux. The Chrome Web Store package is prepared locally but is not published or approved by Google.

## Supported now

- Network, fetch/XHR, video-element, and cross-origin iframe capture, including extensionless manifests identified by their response MIME type. A `blob:` player can work when the underlying media requests are detected.
- Direct MP4, WebM, MOV, and M4V files. These are streamed unchanged to the chosen file.
- Standard completed HLS playlists, master-playlist quality selection, relative URLs, and byte ranges when the server honors Range requests.
- MPEG-TS HLS containing supported H.264 video/AAC audio, repackaged as fragmented MP4 with the bundled mux.js library.
- HLS fragmented MP4 with a stable initialization file, copied in order.
- Ordinary AES-128 HLS when its key is accessible to the user, including sequence-derived and explicit IVs. This is separate from DRM systems.
- Captured Referer, Origin, and User-Agent headers, applied only to requests from the download tab through temporary Chrome session rules. Chrome's own login cookies can be used with explicit opt-in; Pullr does not export them.
- Four segments fetched at a time, ordered writes to disk, short retries for transient failures, progress, and cancellation.

## Current technical boundaries

DASH and HLS with separate audio tracks are detected but their merger is not implemented in this first version. Live/unfinished playlists, timeline or codec switches, SAMPLE-AES/DRM, and site-specific webpage extraction are not included. A server may also reject an expired link, login session, or request context. Unsupported streams show an unavailable button or a specific error; there is no paid unlock.

There is no video-duration, file-size, or daily-download quota in the code. Memory use still depends on individual segment sizes and the muxer, and available disk space still limits saves. For safety, playlist metadata larger than 10 MiB is rejected; this is a parser resource boundary, not a limit on the video size.

Closing the download tab or Chrome interrupts the job; there is no resume across browser restarts. A successful write is committed when the file stream closes. On error or Cancel, the file stream is aborted. The native Save As dialog controls overwriting existing files. Cancelling a new save may leave an empty newly chosen file, while incomplete data is discarded.

## Checks

No build step is needed. All executable JavaScript is bundled locally; nothing is fetched for execution.

```sh
node tests/test_dlp.cjs
node tests/test_groups.cjs
node test_stream_capture.js
node test_page_capture.js
node test_background.js
```

The DLP check also accepts an optional output directory to exercise the project's local test fixtures at port 8765. The fixture server and generated media are development-only files and are not part of the store package. See `VALIDATION.md` in the source package for the actual checks performed.

## Components and sources

The capture hooks come from the user's Pullr codebase. Playlist parsing, fetching, retries, AES handling, progress, and disk-save orchestration are implemented in `dlp.js`; the interface and Chrome integration are included here. Container packaging uses [mux.js 6.3.0](https://github.com/videojs/mux.js), bundled with its Apache 2.0 license in `vendor/mux-LICENSE.txt`.

Chrome provides [cross-origin extension requests](https://developer.chrome.com/docs/extensions/develop/concepts/network-requests), [temporary request-header rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest), and [streaming file writes](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access).
