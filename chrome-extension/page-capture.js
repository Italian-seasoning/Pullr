(() => {
  if (window.__pullrPageCaptureInstalled) return;
  Object.defineProperty(window, "__pullrPageCaptureInstalled", { value: true });

  let latestPosterURL = "";

  const normalizedWebURL = (value) => {
    try {
      const url = new URL(value, location.href);
      return ["http:", "https:"].includes(url.protocol) ? url.href : "";
    } catch {
      return "";
    }
  };

  const hlsManifestRole = (text) => {
    if (/#EXT-X-(STREAM-INF|MEDIA):/i.test(text)) return "master";
    if (/#EXTINF:/i.test(text)) return "media";
    return "";
  };

  const report = (value, contentType = "", manifestRole = "") => {
    try {
      const url = new URL(value, location.href);
      if (!["http:", "https:"].includes(url.protocol)) return;
      const message = {
        source: "pullr-page-capture",
        url: url.href,
        contentType: contentType || ""
      };
      if (latestPosterURL) message.posterURL = latestPosterURL;
      if (manifestRole) message.manifestRole = manifestRole;
      window.postMessage(message, "*");
    } catch {}
  };

  const responseType = (response) => {
    try { return response?.headers?.get("content-type") || ""; } catch { return ""; }
  };

  if (typeof window.fetch === "function") {
    const nativeFetch = window.fetch;
    window.fetch = function (...args) {
      const requestedURL = typeof args[0] === "string" || args[0] instanceof URL ? String(args[0]) : args[0]?.url;
      return nativeFetch.apply(this, args).then((response) => {
        const responseURL = response?.url || requestedURL;
        const contentType = responseType(response);
        report(responseURL, contentType);
        if (String(responseURL).includes(".m3u8") || contentType.toLowerCase().includes("mpegurl")) {
          response.clone?.().text().then((text) => {
            const role = hlsManifestRole(text);
            if (role) report(responseURL, contentType, role);
          }).catch(() => {});
        }
        return response;
      });
    };
  }

  if (typeof window.XMLHttpRequest === "function") {
    const nativeOpen = window.XMLHttpRequest.prototype.open;
    window.XMLHttpRequest.prototype.open = function (_method, url, ...rest) {
      this.addEventListener("load", () => {
        let contentType = "";
        try { contentType = this.getResponseHeader("content-type") || ""; } catch {}
        report(this.responseURL || url, contentType);
        try {
          const role = hlsManifestRole(this.responseText || "");
          if (role) report(this.responseURL || url, contentType, role);
        } catch {}
      }, { once: true });
      return nativeOpen.call(this, _method, url, ...rest);
    };
  }

  const reportResource = (entry) => report(entry?.name);
  try {
    performance.getEntriesByType("resource").forEach(reportResource);
    const observer = new PerformanceObserver((list) => list.getEntries().forEach(reportResource));
    observer.observe({ type: "resource", buffered: true });
  } catch {}

  const reportMedia = (root = document) => {
    const videos = root instanceof HTMLVideoElement ? [root] : [...(root.querySelectorAll?.("video") || [])];
    for (const video of videos) {
      latestPosterURL = normalizedWebURL(video.poster) || latestPosterURL;
    }
    if (root instanceof HTMLMediaElement) report(root.currentSrc || root.src);
    if (root instanceof HTMLSourceElement) report(root.src);
    root.querySelectorAll?.("video[src], audio[src], source[src]").forEach((node) => report(node.currentSrc || node.src));
  };

  const startDOMCapture = () => {
    reportMedia();
    new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "attributes") reportMedia(mutation.target);
        mutation.addedNodes.forEach((node) => {
          if (node instanceof Element) reportMedia(node);
        });
      }
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["src", "poster"] });
  };

  if (typeof document !== "undefined") {
    if (document.documentElement) startDOMCapture();
    else document.addEventListener("DOMContentLoaded", startDOMCapture, { once: true });
  }
})();
