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
  let previousTime = 0;
  let pendingSeconds = 0;
  let lastMetadataSignature = "";

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
    const signature = `${current.videoID}|${current.title}|${current.artist}`;
    if (!current.title || signature === lastMetadataSignature) return current;
    lastMetadataSignature = signature;
    void chrome.runtime.sendMessage({ action: "currentMusic", ...current }).catch(() => {});
    return current;
  };

  const flush = () => {
    if (pendingSeconds < 5) return;
    const current = reportMetadata();
    const seconds = Math.min(pendingSeconds, 60);
    pendingSeconds -= seconds;
    void chrome.runtime.sendMessage({ action: "trackListening", ...current, seconds }).catch(() => {});
  };

  const onTimeUpdate = () => {
    const currentTime = video?.currentTime || 0;
    if (video && !video.paused) pendingSeconds += listenedDelta(previousTime, currentTime);
    previousTime = currentTime;
    reportMetadata();
    if (pendingSeconds >= 30) flush();
  };

  const bindVideo = () => {
    const next = document.querySelector("video");
    if (!next || next === video) return;
    flush();
    video?.removeEventListener("timeupdate", onTimeUpdate);
    video?.removeEventListener("pause", flush);
    video?.removeEventListener("ended", flush);
    video = next;
    previousTime = video.currentTime || 0;
    video.addEventListener("timeupdate", onTimeUpdate);
    video.addEventListener("pause", flush);
    video.addEventListener("ended", flush);
    lastMetadataSignature = "";
    reportMetadata();
  };

  bindVideo();
  new MutationObserver(bindVideo).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(bindVideo, 2_000);
  addEventListener("pagehide", flush);
  document.addEventListener("visibilitychange", () => { if (document.hidden) flush(); });
})();
