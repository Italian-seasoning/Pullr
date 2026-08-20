window.addEventListener("message", (event) => {
  if (event.source !== window || event.data?.source !== "pullr-page-capture") return;

  let url;
  try {
    url = new URL(event.data.url);
    if (!["http:", "https:"].includes(url.protocol)) return;
  } catch {
    return;
  }

  let posterURL = "";
  try {
    const poster = new URL(event.data.posterURL);
    if (["http:", "https:"].includes(poster.protocol)) posterURL = poster.href;
  } catch {}

  void chrome.runtime.sendMessage({
    action: "recordPageStream",
    url: url.href,
    posterURL,
    manifestRole: ["master", "media"].includes(event.data.manifestRole) ? event.data.manifestRole : "",
    contentType: String(event.data.contentType || "").slice(0, 200),
    frameURL: location.href,
    origin: location.origin,
    userAgent: navigator.userAgent
  });
});
