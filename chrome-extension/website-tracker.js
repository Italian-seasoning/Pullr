(function (root) {
  function activityForTab(tab) {
    try {
      const url = new URL(tab?.url || "");
      if (!["http:", "https:"].includes(url.protocol)) return null;

      const host = url.hostname.toLowerCase();
      const isYouTube = host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com");
      const site = isYouTube ? "youtube.com" : host.replace(/^www\./, "");
      const title = isYouTube ? String(tab?.title || site).replace(/ - YouTube$/, "").trim().slice(0, 240) : site;
      return {
        site,
        title,
        url: isYouTube ? url.href : `${url.protocol}//${url.host}/`,
        isYouTube
      };
    } catch {
      return null;
    }
  }

  function completedSegment(activity, now = Date.now()) {
    const seconds = (now - Number(activity?.startedAt || now)) / 1_000;
    return activity?.site && seconds >= 1
      ? { ...activity, seconds: Math.round(Math.min(seconds, 90) * 1_000) / 1_000 }
      : null;
  }

  function isTrackingEnabled(settings) {
    return settings?.hoursTrackingEnabled === true;
  }

  function isAllowed(site, sites) {
    return Array.isArray(sites) && sites.some((allowed) =>
      typeof allowed === "string" && (site === allowed || site.endsWith(`.${allowed}`))
    );
  }

  root.PullrWebsiteTracker = { activityForTab, completedSegment, isTrackingEnabled, isAllowed };
})(typeof globalThis !== "undefined" ? globalThis : self);
