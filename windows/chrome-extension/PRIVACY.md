# Pullr privacy

Pullr processes video downloads on the user's computer. There is no developer server, analytics, account, subscription service, or cloud upload.

Clipboard access is used only when the user clicks **Paste link**. Pullr reads the copied text, accepts only a valid HTTP/HTTPS URL without embedded credentials, and opens that link's download tab. It does not monitor clipboard changes or keep unrelated clipboard contents.

The download queue stores only job titles and Chrome tab identifiers in session storage. Save locations and file handles stay inside the corresponding download tab. Queue jobs are removed on completion, cancellation, tab closure/reload, or when Chrome ends the session.

While installed with website access, Pullr observes media-related HTTP/HTTPS requests and page media elements to find videos, including videos in embedded frames. Detected media URLs and limited request context (referring page, Origin, and User-Agent) are kept in Chrome session storage for the current browser session. Captures are cleared when their source tab navigates or closes. A selected capture is briefly handed to its download tab through session storage and removed from that staging entry when opened.

Downloads make network requests to the selected media source, its playlists, segments, redirects, and any referenced ordinary HLS encryption key. Chrome session rules temporarily reproduce captured request headers only for the download tab. These rules are removed after inspection/download and when the page exits; Chrome also removes session rules when the browser session ends.

**Use site login** is off by default. When explicitly selected, the browser is allowed to send applicable existing cookies with download requests. Pullr does not read, export, persist, or send cookies to a developer service.

Users choose a save location using Chrome's file picker. Video data is written to that file on the user's computer. It is not uploaded by Pullr. Uninstalling Pullr removes the extension; users retain files they deliberately saved.

Website access is required to discover embedded media and fetch the user's selected video. The extension does not track browsing time, build a browsing history, sell user data, or inspect unrelated local files. This first version has no remote logging or telemetry.
