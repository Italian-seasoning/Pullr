importScripts("stream-capture.js", "website-tracker.js", "activity-outbox.js");

const keyForTab = (tabId) => `streams:${tabId}`;
const musicKeyForTab = (tabId) => `music:${tabId}`;
const responseHeaderValue = (headers, name) => (headers || []).find((header) => header.name?.toLowerCase() === name)?.value || "";
const requestContextByID = new Map();
const activityKey = "websiteActivity";
const trackingSettingKey = "hoursTrackingEnabled";
const allowedSitesKey = "allowedSites";
let activityRefresh = Promise.resolve();
let activitySettings = null;
let activityAlarmScheduled = false;
let pendingActivity = false;

async function setActivityAlarm(needed) {
  if (needed && !activityAlarmScheduled) {
    await chrome.alarms.create(activityKey, { periodInMinutes: 0.5 });
    activityAlarmScheduled = true;
  } else if (!needed && activityAlarmScheduled) {
    await chrome.alarms.clear(activityKey);
    activityAlarmScheduled = false;
  }
}

async function syncActivity(segment = null) {
  const canRecord = await PullrActivityOutbox.sync(
    chrome.storage.local,
    message => chrome.runtime.sendNativeMessage("app.pullr.native", message),
    segment
  );
  const saved = await chrome.storage.local.get("activityOutbox");
  pendingActivity = Boolean(saved.activityOutbox?.length);
  return canRecord;
}

async function refreshWebsiteActivity(checkpoint = false) {
  if (!PullrWebsiteTracker.isTrackingEnabled(activitySettings)) {
    if (checkpoint && pendingActivity) await syncActivity();
    await setActivityAlarm(pendingActivity);
    return;
  }
  const now = Date.now();
  const [stored, idleState, window] = await Promise.all([
    chrome.storage.session.get(activityKey),
    chrome.idle.queryState(60),
    chrome.windows.getLastFocused({ populate: false }).catch(() => null)
  ]);
  const previous = stored[activityKey];
  let next = null;

  if (idleState === "active" && window?.focused) {
    const [tab] = await chrome.tabs.query({ active: true, windowId: window.id });
    const activity = PullrWebsiteTracker.activityForTab(tab);
    if (activity && PullrWebsiteTracker.isAllowed(activity.site, activitySettings[allowedSitesKey])) {
      next = { ...activity, startedAt: now };
    }
  }

  if (!previous && !next) {
    if (pendingActivity) await syncActivity();
    await setActivityAlarm(pendingActivity);
    return;
  }
  const unchanged = previous && next && previous.site === next.site && previous.url === next.url && previous.title === next.title;
  if (unchanged && !checkpoint) {
    await setActivityAlarm(true);
    return;
  }

  const segment = PullrWebsiteTracker.completedSegment(previous, now);
  const canRecord = await syncActivity(
    segment && PullrWebsiteTracker.isAllowed(segment.site, activitySettings[allowedSitesKey]) ? {
      action: "trackWebsite",
      id: crypto.randomUUID(),
      recordedAt: now / 1000,
      url: segment.url,
      title: segment.title,
      seconds: segment.seconds
    } : null
  );

  if (next && canRecord) await chrome.storage.session.set({ [activityKey]: next });
  else await chrome.storage.session.remove(activityKey);
  await setActivityAlarm(Boolean(next) || pendingActivity);
}

function queueWebsiteActivityRefresh(checkpoint = false) {
  if (activitySettings && !PullrWebsiteTracker.isTrackingEnabled(activitySettings) && !checkpoint) return;
  const refresh = () => refreshWebsiteActivity(checkpoint === true);
  activityRefresh = activityRefresh.then(refresh, refresh);
}

function configureWebsiteActivity() {
  const configure = async () => {
    const settings = await chrome.storage.local.get([trackingSettingKey, allowedSitesKey, "activityOutbox"]);
    try {
      if (PullrWebsiteTracker.isTrackingEnabled(activitySettings)) {
        await refreshWebsiteActivity(true);
      }
    } finally {
      activitySettings = settings;
      pendingActivity = Boolean((await chrome.storage.local.get("activityOutbox")).activityOutbox?.length);
      await chrome.alarms.clear(activityKey);
      activityAlarmScheduled = false;
      if (!PullrWebsiteTracker.isTrackingEnabled(settings)) await chrome.storage.session.remove(activityKey);
    }
    if (PullrWebsiteTracker.isTrackingEnabled(activitySettings)) await refreshWebsiteActivity();
    else await setActivityAlarm(pendingActivity);
  };
  activityRefresh = activityRefresh.then(configure, configure);
  return activityRefresh;
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
  if (message?.action === "videoPlaybackState" && Number.isInteger(sender.tab?.id)) {
    sendResponse({ ok: true });
    return true;
  }

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
    sendResponse({ ok: true, retired: true });
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
  if (alarm.name === activityKey) queueWebsiteActivityRefresh(true);
});
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === "local" && (changes[trackingSettingKey] || changes[allowedSitesKey])) void configureWebsiteActivity();
});
