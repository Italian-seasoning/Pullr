const sendPageButton = document.querySelector("#send-page");
const status = document.querySelector("#status");
const tabTitle = document.querySelector("#tab-title");
const detected = document.querySelector("#detected");
const streamCount = document.querySelector("#stream-count");
const streamList = document.querySelector("#stream-list");
const music = document.querySelector("#music");
const songTitle = document.querySelector("#song-title");
const appleMusicButton = document.querySelector("#apple-music");
const confirmAppleMusicButton = document.querySelector("#confirm-apple-music");
const downloadAudioButton = document.querySelector("#download-audio");
const sendYouTubeButton = document.querySelector("#send-youtube");
const hoursToggle = document.querySelector("#hours-toggle");
const allowSiteButton = document.querySelector("#allow-site");
const allowedSitesList = document.querySelector("#allowed-sites");
const bestAudioPresetID = "3A4B5C6D-7E8F-4091-A120-AAAAAAAAAAAA";
const bestVideoPresetID = "A1B2C3D4-E5F6-47A8-9B10-111111111111";
let preferredStream = null;
let currentMusic = null;
let pendingMusicMatch = null;
let currentSite = null;
let allowedSites = [];

const setStatus = (message) => { status.textContent = message; };
for (const button of document.querySelectorAll('[data-view]')) {
  button.addEventListener('click', () => {
    const tracking = button.dataset.view === 'tracking';
    document.querySelector('#capture-view').hidden = tracking;
    document.querySelector('#tracking-view').hidden = !tracking;
    for (const other of document.querySelectorAll('[data-view]')) other.setAttribute('aria-pressed', String(other === button));
  });
}

function renderTrackingSync(settings) {
  const target = document.querySelector('#tracking-sync');
  const state = settings.websiteTrackingSync;
  target.textContent = !settings.hoursTrackingEnabled ? 'Recording is off.'
    : state === 'full' ? 'Recording paused: reconnect the native helper to save pending time.'
    : state === 'waiting' ? 'Saved in this browser. Waiting for the native helper to sync.'
    : 'Recording locally. Pullr can stay closed.';
  target.classList.toggle('needs-sync', state === 'waiting' || state === 'full');
}
chrome.storage.onChanged.addListener((_changes, area) => {
  if (area === 'local') chrome.storage.local.get(['hoursTrackingEnabled', 'websiteTrackingSync']).then(renderTrackingSync);
});

function isWebURL(value) {
  try {
    return ["http:", "https:"].includes(new URL(value).protocol);
  } catch {
    return false;
  }
}

function isYouTubeURL(value) {
  try {
    const host = new URL(value).hostname;
    return host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com");
  } catch {
    return false;
  }
}

async function activeTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

function renderAllowedSites() {
  allowedSitesList.replaceChildren();
  allowSiteButton.disabled = !currentSite || allowedSites.includes(currentSite);
  allowSiteButton.textContent = currentSite && allowedSites.includes(currentSite)
    ? `${currentSite} is allowed` : `Add ${currentSite || "this website"}`;
  for (const site of allowedSites) {
    const row = document.createElement("div");
    row.className = "allowed-site";
    const label = document.createElement("span");
    label.textContent = site;
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "secondary remove-site";
    remove.textContent = "Remove";
    remove.setAttribute("aria-label", `Stop tracking ${site}`);
    remove.addEventListener("click", async () => {
      allowedSites = allowedSites.filter((value) => value !== site);
      await chrome.storage.local.set({ allowedSites });
      renderAllowedSites();
    });
    row.append(label, remove);
    allowedSitesList.append(row);
  }
}

function streamName(stream) {
  const url = new URL(stream.url);
  const file = url.pathname.split("/").filter(Boolean).pop() || "manifest";
  return `${stream.label} · ${url.hostname} · ${file}`;
}

async function clearCapturedStreams(tabId) {
  if (Number.isInteger(tabId)) {
    await chrome.runtime.sendMessage({ action: "clearStreamsForTab", tabId });
  }
}

async function pageThumbnail(windowId, posterURL) {
  if (isWebURL(posterURL)) return "";
  try {
    return await chrome.tabs.captureVisibleTab(windowId, { format: "jpeg", quality: 55 });
  } catch {
    return "";
  }
}

async function sendToPullr(stream, referrer, tabId, windowId) {
  const { url, kind: captureKind } = stream;
  const thumbnailDataURL = await pageThumbnail(windowId, stream.posterURL);
  try {
    const response = await chrome.runtime.sendNativeMessage("app.pullr.native", {
      action: "add",
      url,
      referrer,
      captureKind,
      userAgent: stream.userAgent || navigator.userAgent,
      origin: stream.origin || "",
      contentType: stream.contentType || "",
      contentLength: stream.contentLength || 0,
      thumbnailURL: stream.posterURL || "",
      thumbnailDataURL
    });
    if (response?.ok) {
      await clearCapturedStreams(tabId);
      setStatus("Sent to Pullr.");
      return;
    }
  } catch {
    // Fall back to the URL scheme when the native host is not installed.
  }

  const params = new URLSearchParams({ url });
  if (isWebURL(referrer)) params.set("referrer", referrer);
  params.set("captureKind", captureKind);
  params.set("userAgent", stream.userAgent || navigator.userAgent);
  if (isWebURL(stream.origin)) params.set("origin", stream.origin);
  if (stream.contentType) params.set("contentType", stream.contentType);
  if (stream.contentLength) params.set("contentLength", String(stream.contentLength));
  if (isWebURL(stream.posterURL)) params.set("thumbnailURL", stream.posterURL);
  await chrome.tabs.create({ url: `pullr://add?${params}`, active: false });
  await clearCapturedStreams(tabId);
  setStatus("Sent to Pullr. Your browser may ask for permission.");
}

async function sendBestAudio(tab) {
  const url = PullrStreamCapture.singleYouTubeVideoURL(tab.url);
  const message = { action: "add", url, presetID: bestAudioPresetID, start: true };
  try {
    const response = await chrome.runtime.sendNativeMessage("app.pullr.native", message);
    if (response?.ok) {
      setStatus("Best audio download started in Pullr.");
      return;
    }
  } catch {}

  const params = new URLSearchParams({ url, presetID: bestAudioPresetID, start: "1" });
  await chrome.tabs.create({ url: `pullr://add?${params}`, active: false });
  setStatus("Sent to Pullr. Your browser may ask for permission.");
}

async function sendYouTubeVideo(tab) {
  const url = PullrStreamCapture.singleYouTubeVideoURL(tab.url);
  const message = { action: "add", url, presetID: bestVideoPresetID, start: true };
  try {
    const response = await chrome.runtime.sendNativeMessage("app.pullr.native", message);
    if (response?.ok) {
      setStatus("H.265 video download started in Pullr.");
      return;
    }
  } catch {}

  const params = new URLSearchParams({ url, presetID: bestVideoPresetID, start: "1" });
  await chrome.tabs.create({ url: `pullr://add?${params}`, active: false });
  setStatus("Sent to Pullr. Your browser may ask for permission.");
}

async function openAppleMusic(tab) {
  const details = currentMusic || { title: tab.title || "", artist: "", url: tab.url };
  pendingMusicMatch = null;
  confirmAppleMusicButton.hidden = true;
  confirmAppleMusicButton.disabled = false;
  setStatus("Matching this song…");
  try {
    const response = await chrome.runtime.sendNativeMessage("app.pullr.native", {
      action: "findAppleMusic",
      title: details.title,
      artist: details.artist || "",
      url: tab.url
    });
    if (response?.ok) {
      setStatus(`Opened ${response.title} by ${response.artist} in Music.`);
      return;
    }
    if (response?.error === "confirm_match" && response.url && response.title && response.artist) {
      pendingMusicMatch = response;
      confirmAppleMusicButton.textContent = `Open ${response.title} — ${response.artist}`;
      confirmAppleMusicButton.hidden = false;
      setStatus("Possible match. Confirm the song and artist before opening.");
      return;
    }
  } catch {}
  setStatus("No confident Apple Music match was found.");
}

function renderStreams(streams, tab, showAll = false) {
  preferredStream = PullrStreamCapture.preferredStream(streams);
  detected.hidden = streams.length === 0;
  streamList.replaceChildren();
  streamCount.textContent = streams.length ? String(streams.length) : "";

  const ordered = preferredStream
    ? [preferredStream, ...streams.filter((stream) => stream.url !== preferredStream.url)]
    : streams;
  const visibleStreams = showAll ? ordered : ordered.slice(0, 1);

  for (const stream of visibleStreams) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "stream";
    const title = document.createElement('strong');
    title.textContent = `↓ Send ${stream.label} to Pullr`;
    const detail = document.createElement('small');
    detail.textContent = streamName(stream);
    button.append(title, detail);
    button.title = stream.url;
    button.addEventListener("click", () => sendToPullr(stream, stream.initiator || tab.url, tab.id, tab.windowId));
    streamList.append(button);
  }

  if (!showAll && ordered.length > 1) {
    const showAllButton = document.createElement("button");
    showAllButton.type = "button";
    showAllButton.className = "stream secondary";
    showAllButton.textContent = `Show ${ordered.length - 1} other candidate${ordered.length === 2 ? "" : "s"}`;
    showAllButton.addEventListener("click", () => renderStreams(streams, tab, true));
    streamList.append(showAllButton);
  }
}

async function refresh() {
  const tab = await activeTab();
  const supported = Boolean(tab?.url && isWebURL(tab.url));
  currentSite = PullrWebsiteTracker.activityForTab(tab)?.site || null;
  renderAllowedSites();

  tabTitle.textContent = tab?.title || "Inspecting this tab";
  sendPageButton.disabled = !supported;
  if (!supported) {
    setStatus("Open a normal web page first.");
    return;
  }

  const youtubeVideo = PullrStreamCapture.isYouTubeVideoURL(tab.url);
  music.hidden = !youtubeVideo;
  if (youtubeVideo) {
    // YouTube's signed media fragments are not standalone downloads.
    renderStreams([], tab);
    const musicResponse = await chrome.runtime.sendMessage({ action: "musicForTab", tabId: tab.id });
    currentMusic = musicResponse?.music || null;
    music.hidden = false;
    songTitle.textContent = currentMusic?.artist
      ? `${currentMusic.title} — ${currentMusic.artist}`
      : (currentMusic?.title || tab.title || "Current YouTube track");
    sendPageButton.disabled = false;
    sendPageButton.textContent = "Download YouTube video · H.265";
    document.querySelector("#capture-help").textContent = "Downloads this video as an H.265 MP4 in Pullr.";
    setStatus("Ready to download. Playback is not required.");
    return;
  }
  const response = await chrome.runtime.sendMessage({ action: "streamsForTab", tabId: tab.id });
  renderStreams(response?.streams || [], tab);
  sendPageButton.disabled = !preferredStream;
  sendPageButton.textContent = preferredStream ? "Send detected video to Pullr" : "No stream detected — play the video first";
  setStatus(preferredStream ? "Ready to send. Downloads open in Pullr." : "Play the video, then reopen this extension.");
}

sendPageButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (!tab?.url || !isWebURL(tab.url)) {
    setStatus("Open a normal web page first.");
    return;
  }
  if (PullrStreamCapture.isYouTubeVideoURL(tab.url)) {
    await sendYouTubeVideo(tab);
    return;
  }
  if (!preferredStream) {
    setStatus("No media stream detected. Keep the video playing, then reopen Pullr.");
    return;
  }
  await sendToPullr(preferredStream, preferredStream.initiator || tab.url, tab.id, tab.windowId);
});

appleMusicButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (tab?.url && isYouTubeURL(tab.url)) await openAppleMusic(tab);
});

confirmAppleMusicButton.addEventListener("click", async () => {
  const match = pendingMusicMatch;
  if (!match) return;
  confirmAppleMusicButton.disabled = true;
  try {
    const response = await chrome.runtime.sendNativeMessage("app.pullr.native", { action: "openAppleMusicMatch", url: match.url });
    if (response?.ok) {
      setStatus(`Opened ${match.title} by ${match.artist} in Music.`);
      pendingMusicMatch = null;
      confirmAppleMusicButton.hidden = true;
      return;
    }
  } catch {}
  setStatus("Could not open this match in Music.");
  confirmAppleMusicButton.disabled = false;
});

downloadAudioButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (tab?.url && isYouTubeURL(tab.url)) await sendBestAudio(tab);
});

sendYouTubeButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (tab?.url && isYouTubeURL(tab.url)) await sendYouTubeVideo(tab);
});

hoursToggle.addEventListener("change", async () => {
  await chrome.storage.local.set({ hoursTrackingEnabled: hoursToggle.checked });
  setStatus(hoursToggle.checked ? "Hours tracking enabled on this Mac." : "Hours tracking is off.");
});

allowSiteButton.addEventListener("click", async () => {
  if (!currentSite || allowedSites.includes(currentSite)) return;
  allowedSites = [...allowedSites, currentSite].sort();
  await chrome.storage.local.set({ allowedSites });
  renderAllowedSites();
  setStatus(`Tracking ${currentSite} while Chrome is focused.`);
});

chrome.storage.local.get(["hoursTrackingEnabled", "allowedSites", "websiteTrackingSync"])
  .then((settings) => {
    hoursToggle.checked = settings.hoursTrackingEnabled === true;
    allowedSites = Array.isArray(settings.allowedSites) ? settings.allowedSites : [];
    renderAllowedSites();
    renderTrackingSync(settings);
  });
refresh().catch(() => setStatus("Pullr could not inspect this tab."));
