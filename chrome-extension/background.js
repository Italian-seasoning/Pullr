importScripts("stream-capture.js", "website-tracker.js");

const keyForTab = (tabId) => `streams:${tabId}`;
const musicKeyForTab = (tabId) => `music:${tabId}`;
const responseHeaderValue = (headers, name) => (headers || []).find((header) => header.name?.toLowerCase() === name)?.value || "";
const requestContextByID = new Map();
const activityKey = "websiteActivity";
const trackingSettingKey = "hoursTrackingEnabled";
let activityRefresh = Promise.resolve();

async function refreshWebsiteActivity() {
  const now = Date.now();
  const [settings, stored, idleState, window] = await Promise.all([
    chrome.storage.local.get(trackingSettingKey),
    chrome.storage.session.get(activityKey),
    chrome.idle.queryState(60),
    chrome.windows.getLastFocused({ populate: false }).catch(() => null)
  ]);
  if (!PullrWebsiteTracker.isTrackingEnabled(settings)) {
    await chrome.storage.session.remove(activityKey);
    return;
  }
  const previous = stored[activityKey];
  let next = null;

  if (idleState === "active" && window?.focused) {
    const [tab] = await chrome.tabs.query({ active: true, windowId: window.id });
    const activity = PullrWebsiteTracker.activityForTab(tab);
    if (activity) next = { ...activity, startedAt: now };
  }

  const segment = PullrWebsiteTracker.completedSegment(previous, now);
  if (segment) {
    await chrome.runtime.sendNativeMessage("app.pullr.native", {
      action: "trackWebsite",
      url: segment.url,
      title: segment.title,
      seconds: segment.seconds
    }).catch(() => {});
  }

  if (next) await chrome.storage.session.set({ [activityKey]: next });
  else await chrome.storage.session.remove(activityKey);
}

function queueWebsiteActivityRefresh() {
  activityRefresh = activityRefresh.then(refreshWebsiteActivity, refreshWebsiteActivity);
}

async function configureWebsiteActivity() {
  const settings = await chrome.storage.local.get(trackingSettingKey);
  if (PullrWebsiteTracker.isTrackingEnabled(settings)) {
    await chrome.alarms.create(activityKey, { periodInMinutes: 0.5 });
    queueWebsiteActivityRefresh();
  } else {
    await chrome.alarms.clear(activityKey);
    await chrome.storage.session.remove(activityKey);
  }
}

void configureWebsiteActivity();

async function streamsForTab(tabId) {
  const key = keyForTab(tabId);
  const stored = await chrome.storage.session.get(key);
  return stored[key] || [];
}

async function updateBadge(tabId) {
  const musicKey = musicKeyForTab(tabId);
  const [streams, stored] = await Promise.all([
    streamsForTab(tabId),
    chrome.storage.session.get(musicKey)
  ]);
  const state = PullrStreamCapture.badgeState(streams.length, Boolean(stored[musicKey]));
  await Promise.all([
    chrome.action.setBadgeBackgroundColor({ tabId, color: state.color }),
    chrome.action.setBadgeText({ tabId, text: state.text }),
    chrome.action.setTitle({ tabId, title: state.title })
  ]).catch(() => {});
}

async function clearStreamsForTab(tabId) {
  await chrome.storage.session.remove(keyForTab(tabId));
  await updateBadge(tabId);
}

async function recordStream(details) {
  if (details.tabId < 0) return;

  const requestContext = requestContextByID.get(details.requestId) || {};

  const classification = PullrStreamCapture.classifyStream(details.url, details.responseHeaders);
  if (!classification) return;

  const key = keyForTab(details.tabId);
  const streams = await streamsForTab(details.tabId);
  const candidate = {
    url: details.url,
    kind: classification.kind,
    label: classification.label,
    initiator: requestContext.referrer || details.initiator || "",
    origin: requestContext.origin || details.origin || "",
    userAgent: requestContext.userAgent || details.userAgent || "",
    contentType: responseHeaderValue(details.responseHeaders, "content-type").split(";")[0],
    contentLength: PullrStreamCapture.responseSize(details.responseHeaders),
    posterURL: details.posterURL || "",
    manifestRole: details.manifestRole || "",
    seenAt: Date.now()
  };
  const next = PullrStreamCapture.mergeStream(streams, candidate).slice(0, 20);

  await chrome.storage.session.set({ [key]: next });
  await updateBadge(details.tabId);
}

chrome.webRequest.onHeadersReceived.addListener(
  (details) => {
    void recordStream(details).finally(() => requestContextByID.delete(details.requestId));
  },
  { urls: ["<all_urls>"] },
  ["responseHeaders"]
);

chrome.webRequest.onSendHeaders.addListener(
  (details) => {
    requestContextByID.set(details.requestId, PullrStreamCapture.safeRequestContext(details.requestHeaders));
  },
  { urls: ["<all_urls>"] },
  ["requestHeaders", "extraHeaders"]
);

chrome.webRequest.onErrorOccurred.addListener(
  (details) => requestContextByID.delete(details.requestId),
  { urls: ["<all_urls>"] }
);

chrome.webRequest.onBeforeRequest.addListener(
  (details) => { void recordStream(details); },
  { urls: ["<all_urls>"] }
);

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.action === "recordPageStream" && Number.isInteger(sender.tab?.id)) {
    const responseHeaders = message.contentType
      ? [{ name: "content-type", value: message.contentType }]
      : [];
    recordStream({
      tabId: sender.tab.id,
      url: message.url,
      responseHeaders,
      initiator: message.frameURL || sender.url || "",
      origin: message.origin || "",
      userAgent: message.userAgent || "",
      posterURL: message.posterURL || "",
      manifestRole: message.manifestRole || ""
    }).then(() => sendResponse({ ok: true }));
    return true;
  }

  if (message?.action === "streamsForTab" && Number.isInteger(message.tabId)) {
    streamsForTab(message.tabId).then((streams) => sendResponse({ streams }));
    return true;
  }

  if (message?.action === "currentMusic" && Number.isInteger(sender.tab?.id)) {
    chrome.storage.session.set({ [musicKeyForTab(sender.tab.id)]: message })
      .then(() => updateBadge(sender.tab.id))
      .then(() => sendResponse({ ok: true }));
    return true;
  }

  if (message?.action === "musicForTab" && Number.isInteger(message.tabId)) {
    const key = musicKeyForTab(message.tabId);
    chrome.storage.session.get(key).then((stored) => sendResponse({ music: stored[key] || null }));
    return true;
  }

  if (message?.action === "trackListening" && Number.isInteger(sender.tab?.id)) {
    chrome.storage.local.get(trackingSettingKey)
      .then((settings) => PullrWebsiteTracker.isTrackingEnabled(settings)
        ? chrome.runtime.sendNativeMessage("app.pullr.native", message)
        : { ok: false, disabled: true })
      .then((response) => sendResponse(response || { ok: false }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }


  if (message?.action === "clearStreamsForTab" && Number.isInteger(message.tabId)) {
    clearStreamsForTab(message.tabId).then(() => sendResponse({ ok: true }));
    return true;
  }

  return false;
});

chrome.tabs.onRemoved.addListener((tabId) => {
  void chrome.storage.session.remove([keyForTab(tabId), musicKeyForTab(tabId)]);
  queueWebsiteActivityRefresh();
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.url) {
    void Promise.all([
      chrome.storage.session.remove(keyForTab(tabId)),
      chrome.storage.session.remove(musicKeyForTab(tabId))
    ]).then(() => updateBadge(tabId));
  }
  if (changeInfo.url || changeInfo.status === "complete") queueWebsiteActivityRefresh();
});

chrome.tabs.onActivated.addListener(queueWebsiteActivityRefresh);
chrome.windows.onFocusChanged.addListener(queueWebsiteActivityRefresh);
chrome.idle.onStateChanged.addListener(queueWebsiteActivityRefresh);
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === activityKey) queueWebsiteActivityRefresh();
});
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === "local" && changes[trackingSettingKey]) void configureWebsiteActivity();
});
