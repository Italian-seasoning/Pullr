importScripts("stream-capture.js");

const keyForTab = (id) => `streams:${id}`;
const requestContexts = new Map();
const pendingByTab = new Map();

// Serialize updates so simultaneous iframe and network reports cannot drop another video.
function forTab(id, work) {
  const next = (pendingByTab.get(id) || Promise.resolve()).then(work, work);
  pendingByTab.set(id, next);
  void next.finally(() => { if (pendingByTab.get(id) === next) pendingByTab.delete(id); }).catch(() => {});
  return next;
}

async function streamsForTab(id) {
  const key = keyForTab(id);
  return (await chrome.storage.session.get(key))[key] || [];
}

async function badge(id, count) {
  await Promise.all([
    chrome.action.setBadgeText({ tabId: id, text: count ? String(count) : "" }),
    chrome.action.setBadgeBackgroundColor({ tabId: id, color: "#366747" })
  ]);
}

function record(details) {
  if (!Number.isInteger(details.tabId) || details.tabId < 0) return Promise.resolve();
  const type = PullrStreamCapture.classifyStream(details.url, details.responseHeaders);
  if (!type) return Promise.resolve();
  const context = requestContexts.get(details.requestId) || {};
  return forTab(details.tabId, async () => {
    const candidate = {
      url: details.url, kind: type.kind, label: type.label,
      referrer: context.referrer || details.frameURL || details.initiator || "",
      origin: context.origin || details.origin || "", userAgent: context.userAgent || details.userAgent || "",
      contentLength: PullrStreamCapture.responseSize(details.responseHeaders), manifestRole: details.manifestRole || "", seenAt: Date.now()
    };
    const relatedURLs = (Array.isArray(details.relatedURLs) ? details.relatedURLs : []).slice(0, 40).filter(value => {
      try { if (typeof value !== "string" || value.length > 8192) return false; const url = new URL(value); return ["http:", "https:"].includes(url.protocol) && !url.username && !url.password; } catch { return false; }
    });
    if (relatedURLs.length) candidate.relatedURLs = relatedURLs;
    const streams = PullrStreamCapture.mergeStream(await streamsForTab(details.tabId), candidate).slice(0, 40);
    await chrome.storage.session.set({ [keyForTab(details.tabId)]: streams });
    await badge(details.tabId, streams.length);
  });
}

chrome.webRequest.onSendHeaders.addListener(details => {
  requestContexts.set(details.requestId, PullrStreamCapture.safeRequestContext(details.requestHeaders));
  if (requestContexts.size > 2000) requestContexts.delete(requestContexts.keys().next().value);
}, { urls: ["http://*/*", "https://*/*"] }, ["requestHeaders", "extraHeaders"]);
chrome.webRequest.onHeadersReceived.addListener(details => {
  void record(details).finally(() => requestContexts.delete(details.requestId)).catch(() => {});
}, { urls: ["http://*/*", "https://*/*"] }, ["responseHeaders"]);
chrome.webRequest.onBeforeRequest.addListener(details => { void record(details).catch(() => {}); }, { urls: ["http://*/*", "https://*/*"] });
chrome.webRequest.onErrorOccurred.addListener(details => requestContexts.delete(details.requestId), { urls: ["http://*/*", "https://*/*"] });

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (["joinDownloadQueue", "leaveDownloadQueue"].includes(message?.action)
    && Number.isInteger(sender.tab?.id) && sender.url?.split("?")[0] === chrome.runtime.getURL("download.html")) {
    changeQueue(sender.tab.id, message.action === "joinDownloadQueue" ? String(message.title || "Video").slice(0, 200) : null)
      .then(queue => reply({ queue }), () => reply({ error: "Could not update the download queue." }));
    return true;
  }
  if (message?.action === "recordPageStream" && Number.isInteger(sender.tab?.id)) {
    record({ ...message, tabId: sender.tab.id, frameURL: sender.url || message.frameURL,
      responseHeaders: [{ name: "content-type", value: String(message.contentType || "").slice(0, 200) }] })
      .then(() => reply({ ok: true }), () => reply({ ok: false }));
    return true;
  }
  if (message?.action === "streamsForTab" && Number.isInteger(message.tabId)) {
    forTab(message.tabId, () => streamsForTab(message.tabId)).then(streams => reply({ streams }), () => reply({ streams: [] }));
    return true;
  }
});

function changeQueue(tabId, title) {
  return forTab("downloadQueue", async () => {
    let queue = (await chrome.storage.session.get("downloadQueue")).downloadQueue || [];
    if (title === null) queue = queue.filter(job => job.tabId !== tabId);
    else if (!queue.some(job => job.tabId === tabId)) queue.push({ tabId, title });
    await chrome.storage.session.set({ downloadQueue: queue });
    return queue;
  });
}

chrome.tabs.onRemoved.addListener(id => {
  void forTab(id, () => chrome.storage.session.remove(keyForTab(id))).catch(() => {});
  void changeQueue(id, null).catch(() => {});
});
chrome.tabs.onUpdated.addListener((id, change) => {
  if (change.status === "loading") void changeQueue(id, null).catch(() => {});
  if (change.status === "loading") void forTab(id, async () => {
    await chrome.storage.session.remove(keyForTab(id)); await badge(id, 0);
  }).catch(() => {});
});
