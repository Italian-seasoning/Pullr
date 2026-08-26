# Pullr Chrome Extension

Load this folder with Chrome or another Chromium browser such as Comet using **Extensions > Developer mode > Load unpacked**.

Run Pullr from `dist/Pullr.app` at least once so macOS registers the `pullr://` URL scheme.

## Native messaging

Install the host for Chrome and Comet:

```sh
../native-host/install.sh
```

The unpacked extension has a stable ID: `eoinkcmbnjeogalchfalgfjbahbfiokj`.

Native messaging sends the tab to Pullr without Chrome's external-protocol prompt.

## YouTube music

On YouTube and YouTube Music, the popup has compact actions to find a confident Apple Music match, download and import the best audio, or add the current video to Pullr's normal download queue. Playback time is recorded locally in `~/Library/Application Support/Pullr/listening-history.jsonl`.

## Website activity

Hours tracking is off by default. Enable **Track website & YouTube hours** in the extension popup to record time for the active Chrome tab only while Chrome is focused and macOS is not idle. The same toggle controls YouTube listening history. General sites are stored by domain; YouTube also keeps the current page title. The local log is `~/Library/Application Support/Pullr/website-activity.jsonl`, summarized with listening time in Pullr's Activity section.

This does not track Safari, other browsers, or time spent in other apps.

See the repository [Privacy](../PRIVACY.md) and [Terms of Use](../TERMS.md).

After updating the unpacked extension, click **Reload** for Pullr on `chrome://extensions` so Chrome picks up the new content script.

## Embedded streams

The extension watches network responses in the current browser session for HLS and MPEG-DASH manifests. Start playback, reopen the Pullr extension, then choose a detected stream. URLs are kept in session storage and removed when the tab closes.

The extension detects manifests requested by the page. It does not decrypt DRM, bypass access controls, or automatically copy browser cookies.

Without the native host, the extension falls back to:

```text
pullr://add?url=<encoded-url>
```
