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

On YouTube and YouTube Music, the popup can open a confident catalog match in Apple Music or start a **Best YouTube Audio** download that imports into Music when it finishes. Playback time is recorded locally in `~/Library/Application Support/Pullr/listening-history.jsonl` and summarized in Pullr's Listening section.

After updating the unpacked extension, click **Reload** for Pullr on `chrome://extensions` so Chrome picks up the new content script.

## Embedded streams

The extension watches network responses in the current browser session for HLS and MPEG-DASH manifests. Start playback, reopen the Pullr extension, then choose a detected stream. URLs are kept in session storage and removed when the tab closes.

The extension detects manifests requested by the page. It does not decrypt DRM, bypass access controls, or automatically copy browser cookies.

Without the native host, the extension falls back to:

```text
pullr://add?url=<encoded-url>
```
