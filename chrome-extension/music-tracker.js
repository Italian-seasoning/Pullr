(() => {
  const cleanTitle = (value) => String(value || "")
    .replace(/\s+-\s+YouTube(?: Music)?$/i, "")
    .replace(/\s*[\[(](official (music )?video|official audio|lyrics?|lyric video|hd|4k)[^\])]*[\])]/ig, "")
    .trim();

  const splitTitle = (value, fallbackArtist = "") => {
    const title = cleanTitle(value);
    if (title.includes(" • ")) {
      const [song, artist] = title.split(" • ");
      return { title: song.trim(), artist: artist.trim() || fallbackArtist };
    }
    if (title.includes(" - ")) {
      const [artist, ...song] = title.split(" - ");
      if (fallbackArtist && artist.trim().toLocaleLowerCase() !== fallbackArtist.trim().toLocaleLowerCase()) {
        return { title, artist: fallbackArtist };
      }
      if (!fallbackArtist && /^(?:super |ultra |hyper )?(?:slowed|sped up)\b/i.test(song.join(" - ").trim())) {
        return { title, artist: "" };
      }
      return { title: song.join(" - ").trim(), artist: artist.trim() || fallbackArtist };
    }
    return { title, artist: fallbackArtist };
  };

  const listenedDelta = (previous, current) => {
    const delta = Number(current) - Number(previous);
    return delta > 0 && delta <= 5 ? delta : 0;
  };

  globalThis.PullrMusicTracker = { cleanTitle, splitTitle, listenedDelta };
  if (typeof document === "undefined" || typeof chrome === "undefined") return;

  let video = null;
  let lastMetadataSignature = "";
  const metadataRegions = "title, ytmusic-player-bar, ytd-watch-metadata, #owner, ytd-channel-name";

  const text = (selector) => document.querySelector(selector)?.textContent?.trim() || "";
  const metadata = () => {
    const pageTitle = text("ytmusic-player-bar .title")
      || text("h1.ytd-watch-metadata yt-formatted-string")
      || document.title;
    const channel = (text("ytmusic-player-bar .byline a")
      || text("#owner #channel-name a")
      || text("ytd-channel-name a"))
      .replace(/\s+-\s+Topic$/i, "")
      .trim();
    const parsed = splitTitle(pageTitle, channel);
    const url = new URL(location.href);
    const videoID = url.searchParams.get("v") || (url.pathname.startsWith("/shorts/") ? url.pathname.split("/")[2] : "");
    return {
      title: parsed.title,
      artist: parsed.artist,
      url: url.href,
      videoID,
      duration: Number.isFinite(video?.duration) ? video.duration : 0,
      thumbnailURL: videoID ? `https://i.ytimg.com/vi/${encodeURIComponent(videoID)}/hqdefault.jpg` : ""
    };
  };

  const reportMetadata = () => {
    const current = metadata();
    const signature = `${current.videoID}|${current.title}|${current.artist}|${current.duration}`;
    if (!current.title || signature === lastMetadataSignature) return current;
    lastMetadataSignature = signature;
    void chrome.runtime.sendMessage({ action: "currentMusic", ...current }).catch(() => {});
    return current;
  };

  const bindVideo = () => {
    const next = document.querySelector("video");
    if (!next || next === video) return;
    for (const event of ["loadedmetadata", "durationchange", "play"]) video?.removeEventListener(event, reportMetadata);
    video = next;
    for (const event of ["loadedmetadata", "durationchange", "play"]) video.addEventListener(event, reportMetadata);
    lastMetadataSignature = "";
    reportMetadata();
  };

  bindVideo();
  new MutationObserver((records) => {
    if (!video?.isConnected) bindVideo();
    if (records.some(record => {
      const target = record.target.nodeType === 3 ? record.target.parentElement : record.target;
      return target?.closest?.(metadataRegions) || Array.from(record.addedNodes || []).some(node => node.matches?.(metadataRegions));
    })) reportMetadata();
  }).observe(document.documentElement, { childList: true, characterData: true, subtree: true });
})();
