# Install Pullr in Chrome on Windows

Requires desktop Chrome 125 or newer. This distribution runs entirely inside Chrome.

1. Download [PullrChrome.zip](https://github.com/Italian-seasoning/Pullr/raw/refs/heads/windows-distribution/windows/packages/PullrChrome.zip).
2. Right-click the ZIP and choose **Extract All**. Keep the extracted folder in a permanent location.
3. Open `chrome://extensions` and enable **Developer mode**.
4. Click **Load unpacked**. Choose the extracted folder that contains `manifest.json`.
5. Pin Pullr using Chrome's Extensions menu. Reload video pages that were open before installation.

## Download a video

Play the video on its webpage, open Pullr, and click **Refresh**. Select **Download** next to the video. In its download tab, choose a quality if offered, edit the filename, and click **Download** to choose where to save it.

For a copied direct-video or M3U8 URL, click **Paste link**. Pullr reads the clipboard only when you click this button. Ordinary webpage links may not be downloadable media URLs.

If the site needs your login, select **Use site login**, then **Check video**. This lets Chrome include the site's existing cookies for this download. Pullr does not export them.

Every video has its own download tab. After you choose its save location, it joins the queue. Jobs run one at a time; the popup's **Downloads** list lets you reopen their tabs. Keep Chrome and those tabs open until they show **Saved**. **Cancel** or closing a job's tab releases its queue slot. Closing Chrome ends the queue; restart/resume is not supported.

## Update or remove

Finish or cancel active jobs before updating. Extract the new ZIP into the existing extension folder, then click **Reload** on Pullr's card in `chrome://extensions`. Re-enable the extension if Chrome asks about new permissions.

To uninstall, click **Remove** on its card. Videos you already saved remain on disk.

## Compatibility

Supported now: direct MP4/WebM/MOV/M4V files, completed HLS with combined audio/video, HLS quality selection, byte ranges, supported MPEG-TS to MP4 packaging, fragmented MP4, and ordinary AES-128 HLS with accessible keys.

DASH, separate audio-track merging, DRM, live recording, codec/timeline switches, site-specific extractors, and restart/resume are not implemented. Expired URLs or site restrictions can prevent a download. No daily caps, accounts, subscriptions, or artificial wait timers are implemented.

Chrome integration was exercised on macOS with local fixtures. Windows Chrome, the native Windows Save As dialog, and the OS clipboard permission flow still need a manual smoke test. See [validation](chrome-extension/VALIDATION.md) and [privacy](chrome-extension/PRIVACY.md).
