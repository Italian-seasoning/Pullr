# Pullr Privacy

Pullr is local software. The developer does not receive website activity, listening history, downloads, settings, or diagnostics. Pullr has no user accounts, analytics, advertising SDKs, telemetry service, or tracking server.

## Hours tracking

Website and YouTube hours tracking is **off by default**. It starts only when you enable **Track website & YouTube hours** in the Chrome extension.

While enabled, Pullr records time only for the active Chrome tab while Chrome is focused and macOS is not idle. It stores:

- the website domain and elapsed time;
- the YouTube page title when the active site is YouTube;
- YouTube listening details reported by the page, such as title, artist, video ID, and elapsed playback time.

For non-YouTube sites, Pullr does not store page titles, paths, query strings, or page contents. Activity records stay in `~/Library/Application Support/Pullr` with permissions limited to the current macOS user. Turning the toggle off stops new time records. Existing records remain until you clear Activity history in Pullr or delete the local files.

## Other network activity

Pullr contacts third parties only for a feature you use: requested media sites for metadata/downloads, Apple’s catalog when you request an Apple Music match, GitHub Releases for app updates, and dependency update sources when you request an update. Those services have their own terms and privacy policies.

## Source and releases

The public repository and release packages must not contain local activity files, download history, diagnostics, settings, credentials, private signing keys, or absolute home-directory paths. Generated builds and common local-data filenames are excluded from Git.

Last updated: 2026-08-23.
