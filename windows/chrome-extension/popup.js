const list = document.querySelector("#stream-list"), status = document.querySelector("#status");

async function openDownload(request) {
  try {
    const id = crypto.randomUUID();
    await chrome.storage.session.set({ [`capture:${id}`]: request });
    await chrome.tabs.create({ url: `${chrome.runtime.getURL("download.html")}?id=${id}` });
  } catch (error) { status.textContent = "Could not open the download: " + error.message; }
}

async function refresh() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    document.querySelector("#tab-title").textContent = tab?.title || "Open a webpage first";
    const supported = /^https?:\/\//i.test(tab?.url || "");
    const captured = supported ? await chrome.runtime.sendMessage({ action: "streamsForTab", tabId: tab.id }) : {};
    const streams = PullrStreamCapture.groupedStreams(captured.streams || []);
    const best = PullrStreamCapture.preferredStream(streams);
    const ordered = best ? [best, ...streams.filter(stream => stream !== best)] : [];
    document.querySelector("#count").textContent = `(${ordered.length})`; list.replaceChildren();
    for (const stream of ordered) {
      const card = document.createElement("article"); card.className = "stream";
      const info = document.createElement("div"); info.className = "stream-info";
      const heading = document.createElement("strong"); heading.textContent = tab.title || "Video"; heading.title = heading.textContent;
      const detail = document.createElement("p"); const parsed = new URL(stream.url);
      detail.textContent = `${stream.label} · ${parsed.hostname}`;
      const actions = document.createElement("div"); actions.className = "actions";
      const download = document.createElement("button"); download.className = "primary"; download.type = "button";
      download.textContent = stream.kind === "dash" ? "Unsupported" : "Download";
      download.disabled = stream.kind === "dash";
      download.addEventListener("click", () => openDownload({ ...stream, title: tab.title || "Video", referrer: stream.referrer || tab.url }));
      const copy = document.createElement("button"); copy.type = "button"; copy.textContent = "Copy link";
      copy.addEventListener("click", async () => {
        try { await navigator.clipboard.writeText(stream.url); status.textContent = "Link copied."; }
        catch { status.textContent = "Could not copy the link."; }
      });
      actions.append(download, copy); info.append(heading, detail); card.append(info, actions); list.append(card);
    }
    status.textContent = ordered.length ? "" : "Play a video, then Refresh. Reload older tabs.";
  } catch (error) { status.textContent = "Could not inspect the page: " + error.message; }
}
document.querySelector("#refresh").addEventListener("click", refresh);
document.querySelector("#paste").addEventListener("click", async () => {
  try {
    const text = (await navigator.clipboard.readText()).trim();
    if (text.length > 8192) throw new Error();
    const url = new URL(text);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error();
    await openDownload({ url: url.href, title: "Video" });
  } catch { status.textContent = "Copy a video URL, then Paste link."; }
});
async function renderQueue() {
  const { downloadQueue = [] } = await chrome.storage.session.get("downloadQueue");
  document.querySelector("#queue-section").hidden = !downloadQueue.length;
  document.querySelector("#queue-count").textContent = `(${downloadQueue.length})`;
  const queueList = document.querySelector("#queue-list"); queueList.replaceChildren();
  for (const [index, job] of downloadQueue.entries()) {
    const row = document.createElement("article"); row.className = "stream";
    const info = document.createElement("div"); info.className = "stream-info";
    const title = document.createElement("strong"); title.textContent = job.title;
    const state = document.createElement("p"); state.textContent = index ? "Queued" : "Downloading";
    const open = document.createElement("button"); open.type = "button"; open.textContent = "Open";
    open.addEventListener("click", async () => {
      try { const tab = await chrome.tabs.update(job.tabId, { active: true }); await chrome.windows.update(tab.windowId, { focused: true }); window.close(); }
      catch { status.textContent = "This download tab has closed."; }
    });
    info.append(title, state); row.append(info, open); queueList.append(row);
  }
}
chrome.storage.onChanged.addListener((changes, area) => { if (area === "session" && changes.downloadQueue) void renderQueue(); });
void renderQueue();
void refresh();
