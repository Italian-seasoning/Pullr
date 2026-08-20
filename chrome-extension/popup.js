const sendPageButton = document.querySelector("#send-page");
const status = document.querySelector("#status");
const tabTitle = document.querySelector("#tab-title");
const detected = document.querySelector("#detected");
const streamCount = document.querySelector("#stream-count");
const streamList = document.querySelector("#stream-list");
const music = document.querySelector("#music");
const songTitle = document.querySelector("#song-title");
const appleMusicButton = document.querySelector("#apple-music");
const downloadAudioButton = document.querySelector("#download-audio");
const bestAudioPresetID = "3A4B5C6D-7E8F-4091-A120-AAAAAAAAAAAA";
let preferredStream = null;
let currentMusic = null;

const setStatus = (message) => { status.textContent = message; };

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

async function openAppleMusic(tab) {
  const details = currentMusic || { title: tab.title || "", artist: "", url: tab.url };
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
    button.textContent = streamName(stream);
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

  tabTitle.textContent = tab?.title || "Inspecting this tab";
  sendPageButton.disabled = !supported;
  if (!supported) {
    setStatus("Open a normal web page first.");
    return;
  }

  const response = await chrome.runtime.sendMessage({ action: "streamsForTab", tabId: tab.id });
  renderStreams(response?.streams || [], tab);
  if (isYouTubeURL(tab.url)) {
    const musicResponse = await chrome.runtime.sendMessage({ action: "musicForTab", tabId: tab.id });
    currentMusic = musicResponse?.music || null;
    music.hidden = false;
    songTitle.textContent = currentMusic?.artist
      ? `${currentMusic.title} — ${currentMusic.artist}`
      : (currentMusic?.title || tab.title || "Current YouTube track");
  }
  sendPageButton.disabled = !preferredStream;
  sendPageButton.textContent = preferredStream ? "Review detected stream" : "No stream detected";
  setStatus(preferredStream ? "Ready to send the most recent detected manifest." : "Play the video, then reopen Pullr.");
}

sendPageButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (!tab?.url || !isWebURL(tab.url)) {
    setStatus("Open a normal web page first.");
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

downloadAudioButton.addEventListener("click", async () => {
  const tab = await activeTab();
  if (tab?.url && isYouTubeURL(tab.url)) await sendBestAudio(tab);
});

refresh().catch(() => setStatus("Pullr could not inspect this tab."));
