# Pullr Chrome Extension

Load this folder with Chrome or another Chromium browser such as Comet using **Extensions > Developer mode > Load unpacked**.

Open Pullr at least once so macOS registers the `pullr://` URL scheme.

## Native messaging

Install the host for Chrome and Comet:

```sh
../native-host/install.sh
```

The unpacked extension has a stable ID: `eoinkcmbnjeogalchfalgfjbahbfiokj`.

Native messaging sends the tab to Pullr without Chrome's external-protocol prompt.

## YouTube music

On a YouTube video, the main **Download YouTube video · H.265** button downloads that single video directly in Pullr. It does not require playback or embedded-stream detection. Both video buttons select the Best MP4 preset and start the download; Pullr converts the finished video to H.265. The native helper and URL-scheme fallback carry the same preset and start action.

On YouTube and YouTube Music, the popup has compact actions to find a confident Apple Music match, download and import the best audio, or add the current video to Pullr's normal download queue. Optional YouTube time tracking follows the website activity settings below.

If the video does not clearly identify the artist, Pullr shows a possible match for you to confirm before opening it in Music.

## Website activity

Hours tracking is off by default. Add each website in the extension popup, then enable **Track allowed websites**. Pullr counts time on the active Chrome tab while Chrome is focused and macOS is not idle, whether or not video is playing. An allowed domain includes its subdomains; all other sites are ignored. General sites are stored by domain; YouTube also keeps the current page title. The local log is `~/Library/Application Support/Pullr/website-activity.jsonl`, summarized in Pullr's Activity section. Removing a site stops new records but does not erase its existing history.

Tracking follows browser events, with a 30-second checkpoint during eligible active sessions. When recording is disabled or ineligible, an alarm runs only while saved activity is waiting to sync. YouTube metadata follows relevant page changes without a polling timer; native tracking messages load only the modules needed to save activity.

This does not track Safari, other browsers, or time spent in other apps.

See the repository [Privacy](../PRIVACY.md) and [Terms of Use](../TERMS.md).

The app updater does not update the browser extension or native helper. After replacing the unpacked extension and helper, run `../native-host/install.sh` from the new folder, click **Reload** for Pullr on `chrome://extensions`, and refresh open YouTube tabs. Keep the extracted folder in place; Chrome and the native host use its files directly.

## Embedded streams

The extension watches network responses in the current browser session for HLS and MPEG-DASH manifests. Start playback, reopen the Pullr extension, then choose a detected stream. URLs are kept in session storage and removed when the tab closes.

The extension detects manifests requested by the page. It does not decrypt DRM, bypass access controls, or automatically copy browser cookies.

Without the native host, the extension falls back to:

```text
pullr://add?url=<encoded-url>
```
