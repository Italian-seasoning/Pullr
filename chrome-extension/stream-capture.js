(function (root) {
  function headerValue(headers, name) {
    const match = (headers || []).find((header) => header.name?.toLowerCase() === name);
    return match?.value?.toLowerCase() || "";
  }

  function classifyStream(url, responseHeaders = []) {
    let path;
    try {
      const parsedURL = new URL(url);
      if (!["http:", "https:"].includes(parsedURL.protocol)) return null;
      path = parsedURL.pathname.toLowerCase();
    } catch {
      return null;
    }

    const contentType = headerValue(responseHeaders, "content-type");
    if (/\.(ts|m4s)$/.test(path)) return null;
    if (path.includes(".m3u8") || contentType.includes("mpegurl")) {
      return { kind: "hls", label: "HLS" };
    }
    if (path.includes(".mpd") || contentType.includes("dash+xml")) {
      return { kind: "dash", label: "MPEG-DASH" };
    }
    if (/\.(mp4|webm|mov|m4v)$/.test(path) || contentType.startsWith("video/")) {
      return { kind: "direct", label: "Direct video" };
    }
    return null;
  }

  function preferredStream(streams) {
    return [...streams].sort((left, right) => score(right) - score(left))[0] || null;
  }

  const volatileQueryKeys = new Set([
    "token", "sig", "signature", "expires", "exp", "policy", "key-pair-id",
    "auth", "session", "range", "start", "end", "rn", "rbuf", "bytestart", "byteend", "_"
  ]);

  function streamIdentity(stream) {
    try {
      const url = new URL(stream.url);
      const stableQuery = [...url.searchParams.entries()]
        .filter(([key]) => !volatileQueryKeys.has(key.toLowerCase()))
        .sort(([left], [right]) => left.localeCompare(right));
      url.search = new URLSearchParams(stableQuery).toString();
      url.hash = "";
      return `${stream.kind || "media"}:${url.href}`;
    } catch {
      return `${stream.kind || "media"}:${stream.url}`;
    }
  }

  function mergeStream(streams, candidate) {
    const identity = streamIdentity(candidate);
    const existing = streams.find((stream) => (stream.identity || streamIdentity(stream)) === identity) || {};
    const usefulCandidate = Object.fromEntries(
      Object.entries(candidate).filter(([, value]) => value !== "" && value !== null && value !== undefined && value !== 0)
    );
    return [{ ...existing, ...usefulCandidate, identity }, ...streams.filter((stream) => (stream.identity || streamIdentity(stream)) !== identity)];
  }

  function score(stream) {
    const typeScore = stream.kind === "hls" ? 300 : stream.kind === "dash" ? 280 : 100;
    const url = String(stream.url || "").toLowerCase();
    const manifestScore = stream.manifestRole === "master" ? 200 : stream.manifestRole === "media" ? 20 : 0;
    const masterNameScore = /(?:master|manifest|playlist)[^/]*\.m3u8/.test(url) ? 50 : 0;
    const decoyPenalty = /(big[_-]?buck[_-]?bunny|\/ads?[\/-]|trailer|preview|sample|promo)/.test(url) ? 500 : 0;
    return typeScore + manifestScore + masterNameScore - decoyPenalty + Math.min(Number(stream.contentLength || 0) / 10_000_000, 20);
  }

  function safeRequestContext(headers) {
    const context = {};
    for (const header of headers || []) {
      const name = header.name?.toLowerCase();
      if (name === "referer") context.referrer = header.value || "";
      if (name === "origin") context.origin = header.value || "";
      if (name === "user-agent") context.userAgent = header.value || "";
    }
    return context;
  }

  function responseSize(headers) {
    const value = (name) => (headers || []).find((header) => header.name?.toLowerCase() === name)?.value || "";
    const total = Number(value("content-range").split("/").pop());
    return Number.isFinite(total) && total > 0 ? total : Number(value("content-length")) || 0;
  }

  function singleYouTubeVideoURL(value) {
    try {
      const url = new URL(value);
      const host = url.hostname.toLowerCase();
      if (!(host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com"))) return value;
      const videoID = host === "youtu.be"
        ? url.pathname.split("/").filter(Boolean)[0]
        : (url.searchParams.get("v") || (url.pathname.startsWith("/shorts/") ? url.pathname.split("/")[2] : ""));
      if (!videoID) return value;
      const single = new URL("/watch", host === "youtu.be" ? "https://www.youtube.com" : url.origin);
      single.searchParams.set("v", videoID);
      return single.href;
    } catch {
      return value;
    }
  }

  function badgeState(streamCount, isTracking) {
    if (isTracking) {
      return { text: "ON", color: "#137333", title: "Pullr is tracking this YouTube tab" };
    }
    if (streamCount > 0) {
      return { text: String(streamCount), color: "#297aed", title: `Pullr detected ${streamCount} media streams` };
    }
    return { text: "", color: "#297aed", title: "Pullr" };
  }

  root.PullrStreamCapture = {
    classifyStream,
    preferredStream,
    streamIdentity,
    mergeStream,
    safeRequestContext,
    responseSize,
    singleYouTubeVideoURL,
    badgeState
  };
})(globalThis);
