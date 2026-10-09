# Chrome Web Store listing draft

**Name:** Pullr — Video Downloader

**Short description:** Find embedded videos and save direct files or standard HLS streams locally. No account, daily quota, or desktop app.

**Description:**

Play the video, open Pullr, and click Download. Pullr finds embedded videos in normal web pages and frames, and opens a compact dark Chrome tab where you can select a quality and save location. Related HLS quality streams are grouped when their manifest confirms the relationship.

Pullr saves supported direct video files and completed standard HLS/M3U8 videos to your computer. Downloads are written incrementally to disk, with visible progress and cancellation. Choose a save location for each video; the queue downloads one at a time. There are no daily quotas, artificial wait timers, subscriptions, or desktop-helper installs.

This first release supports combined audio/video HLS, supported MPEG-TS to MP4 packaging, fragmented MP4, byte ranges, and ordinary AES-128 HLS when its key is accessible. DASH and separate-audio mergers, live streams, codec/timeline switches, protected formats, and webpage-specific extraction are not included. Sites may reject inaccessible or expired streams.

Pullr has no developer server or analytics. Existing site login cookies can be used only if you select the visible login-session checkbox. Downloads and processing stay on your computer.

**Single purpose:** Discover and save the user's selected supported embedded video locally.

**Permission explanations:**

- Website access and webRequest: identify manifests/direct media and retain the request context needed to fetch the chosen stream, including cross-origin embedded frames.
- activeTab/tabs: identify the current page, open the user's download tab, and prevent that tab from being discarded during an active download.
- storage: keep detected streams briefly in session storage and hand the selected stream to the download tab. No cloud synchronization is used.
- clipboardRead: read a copied video URL only after the user clicks Paste link. Clipboard contents are not monitored.
- declarativeNetRequestWithHostAccess: temporarily preserve Referer, Origin, and User-Agent only for the download tab's media requests. Session rules are removed after use.

**Remote code:** None. All scripts and the licensed muxer are included in the extension archive.

**Privacy:** Publish the included PRIVACY.md at a public privacy-policy URL and enter that URL in the store listing. No privacy policy URL, developer contact, or account details have been invented.

**Before submission:** Test the native Save As dialog and target OS/browser; select the actual developer account/contact information; provide the public privacy URL and required store graphics; then submit the package for Google's review. The included ZIP is a local extension package, not a published store listing.
