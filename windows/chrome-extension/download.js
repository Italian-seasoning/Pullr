const urlField = document.querySelector("#url"), status = document.querySelector("#status"), progress = document.querySelector("#progress");
const inspectButton = document.querySelector("#inspect"), saveButton = document.querySelector("#save"), cancelButton = document.querySelector("#cancel");
const quality = document.querySelector("#quality"), login = document.querySelector("#use-login"), filename = document.querySelector("#filename");
const percent = document.querySelector("#percent");
const transfer = document.querySelector(".transfer");
let request = { url: "", title: "Video" }, plan, controller, active = false, ruleId, currentTab;

function options() { return { signal: controller.signal, useLogin: login.checked }; }
function phase(state) {
  transfer.dataset.state = state;
  saveButton.textContent = state === "complete" ? "Download again" : "Download";
}

async function waitForTurn(signal) {
  const response = await chrome.runtime.sendMessage({ action: "joinDownloadQueue", title: request.title });
  if (response.error) throw new Error(response.error);
  return new Promise((resolve, reject) => {
    const finish = error => {
      chrome.storage.onChanged.removeListener(changed); signal.removeEventListener("abort", aborted);
      error ? reject(error) : resolve();
    };
    const aborted = () => finish(new DOMException("Cancelled", "AbortError"));
    const update = async () => {
      try {
        const { downloadQueue = [] } = await chrome.storage.session.get("downloadQueue");
        if (signal.aborted) return aborted();
        const position = downloadQueue.findIndex(job => job.tabId === currentTab.id);
        if (position === 0) return finish();
        if (position < 0) return finish(new Error("This download left the queue. Try again."));
        phase("waiting"); status.textContent = `Queued · ${position} ahead`;
      } catch (error) { finish(error); }
    };
    const changed = (changes, area) => { if (area === "session" && changes.downloadQueue) void update(); };
    chrome.storage.onChanged.addListener(changed); signal.addEventListener("abort", aborted, { once: true });
    void update();
  });
}
function setBusy(busy) {
  for (const element of [urlField, inspectButton, login, quality, filename]) element.disabled = busy;
  saveButton.disabled = busy || !plan; cancelButton.disabled = !busy;
}

async function requestHeaders() {
  const headers = [];
  for (const [header, value] of [["Referer", request.referrer], ["Origin", request.origin], ["User-Agent", request.userAgent]]) {
    if (!value) continue;
    if (String(value).length > 500 || /[\r\n]/.test(value)) continue;
    if (header !== "User-Agent") {
      try { const valid = PullrDlp.webURL(value); headers.push({ header, operation: "set", value: header === "Origin" ? new URL(valid).origin : valid }); } catch { }
    } else headers.push({ header, operation: "set", value });
  }
  if (!headers.length) return;
  await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [ruleId], addRules: [{ id: ruleId, priority: 1,
    action: { type: "modifyHeaders", requestHeaders: headers },
    condition: { initiatorDomains: [chrome.runtime.id], tabIds: [currentTab.id], resourceTypes: ["xmlhttprequest"] }
  }] });
}

async function removeHeaders() {
  if (ruleId) await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [ruleId] }).catch(() => {});
}

async function checkVideo(index = 0) {
  if (active) return;
  controller?.abort(); controller = new AbortController();
  active = true; setBusy(true); plan = null;
  phase("checking"); status.textContent = "Checking video…"; progress.value = 0;
  try {
    request = { ...request, url: PullrDlp.webURL(urlField.value) };
    await requestHeaders();
    plan = await PullrDlp.inspect(request, options(), index);
    if (index === 0) {
      quality.replaceChildren();
      for (const [i, variant] of plan.variants.entries()) { const option = document.createElement("option"); option.value = String(i); option.textContent = variant.label; quality.append(option); }
      document.querySelector("#quality-field").hidden = !plan.variants.length;
    }
    filename.value = filename.value.replace(/\.[a-z0-9]{2,5}$/i, "") + "." + plan.extension;
    const seconds = Math.round(plan.duration || 0);
    const duration = seconds ? `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}` : "";
    phase("ready"); status.textContent = [plan.variants[Number(quality.value)]?.label, duration].filter(Boolean).join(" · ") || "Ready to save";
  } catch (error) { phase("error"); status.textContent = error.name === "AbortError" ? "Check cancelled." : error.message; }
  finally { await removeHeaders(); active = false; setBusy(false); }
}

async function saveVideo() {
  if (active || !plan) return;
  let handle;
  try {
    handle = await showSaveFilePicker({ suggestedName: filename.value, types: [{ description: "Video", accept: { [plan.extension === "webm" ? "video/webm" : "video/mp4"]: ["." + plan.extension] } }] });
  } catch (error) { if (error.name !== "AbortError") status.textContent = error.message; return; }
  controller = new AbortController(); active = true; setBusy(true); phase("waiting"); status.textContent = "Joining queue…"; progress.value = 0; percent.textContent = "0%";
  let writable;
  try {
    await chrome.tabs.update(currentTab.id, { autoDiscardable: false });
    await waitForTurn(controller.signal);
    if (controller.signal.aborted) throw new DOMException("Cancelled", "AbortError");
    await requestHeaders();
    writable = await handle.createWritable();
    phase("downloading"); status.textContent = "Downloading…";
    await PullrDlp.save(plan, writable, options(), update => {
      if (update.percent === null) progress.removeAttribute("value"); else progress.value = update.percent;
      percent.textContent = update.complete ? "Saved" : update.percent === null ? "…" : `${Math.floor(update.percent)}%`;
      const size = (update.bytes / 1024 / 1024).toFixed(1) + " MB";
      if (update.complete) phase("complete");
      status.textContent = update.complete ? `Saved ${handle.name} · ${size}` : `Downloading · ${size}`;
    });
  } catch (error) {
    await writable?.abort().catch(() => {});
    status.textContent = error.name === "AbortError" ? "Cancelled; save discarded." : "Download failed: " + error.message;
    phase("error"); progress.value = 0;
  } finally {
    await chrome.runtime.sendMessage({ action: "leaveDownloadQueue" }).catch(() => {});
    await removeHeaders(); await chrome.tabs.update(currentTab.id, { autoDiscardable: true }).catch(() => {});
    active = false; setBusy(false);
  }
}

inspectButton.addEventListener("click", () => checkVideo());
quality.addEventListener("change", () => checkVideo(Number(quality.value)));
saveButton.addEventListener("click", saveVideo);
cancelButton.addEventListener("click", () => controller?.abort());
urlField.addEventListener("input", () => { plan = null; phase("idle"); saveButton.disabled = true; request = { url: urlField.value, title: request.title }; status.textContent = "Check video to continue."; });
login.addEventListener("change", () => { plan = null; phase("idle"); saveButton.disabled = true; status.textContent = "Recheck to apply the login setting."; });
window.addEventListener("beforeunload", event => { if (active) { event.preventDefault(); event.returnValue = ""; } });
window.addEventListener("pagehide", () => { controller?.abort(); void removeHeaders(); void chrome.runtime.sendMessage({ action: "leaveDownloadQueue" }).catch(() => {}); });

(async () => {
  try {
    currentTab = await chrome.tabs.getCurrent(); ruleId = 100000 + currentTab.id;
    const id = new URLSearchParams(location.search).get("id");
    if (id) { const key = `capture:${id}`; request = (await chrome.storage.session.get(key))[key] || request; await chrome.storage.session.remove(key); }
    urlField.value = request.url || "";
    document.querySelector("#title").textContent = request.title || "Video";
    let name = (request.title || "video").replace(/[<>:"/\\|?*\x00-\x1f]/g, "_").trim().replace(/[. ]+$/, "").slice(0, 120) || "video";
    if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name)) name = "video_" + name;
    filename.value = name + ".mp4";
    if (request.url) await checkVideo();
  } catch (error) { status.textContent = "Could not open the capture: " + error.message; }
})();
