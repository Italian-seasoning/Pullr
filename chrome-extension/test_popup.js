const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
require("./stream-capture.js");

async function popup({ url, streams = [], nativeAvailable = true, nativeResponse = () => ({ ok: true }) }) {
  const elements = new Map();
  const element = (selector) => {
    if (!elements.has(selector)) elements.set(selector, {
      hidden: false, disabled: false, textContent: "", listeners: {},
      classList: { toggle() {} }, replaceChildren() {}, append() {}, setAttribute() {},
      addEventListener(name, callback) { this.listeners[name] = callback; }
    });
    return elements.get(selector);
  };
  const messages = [], nativeMessages = [], openedTabs = [];
  const context = vm.createContext({
    URL, URLSearchParams, console, PullrStreamCapture: globalThis.PullrStreamCapture,
    PullrWebsiteTracker: { activityForTab: () => null }, navigator: { userAgent: "Test" },
    document: { querySelector: element, querySelectorAll: () => [], createElement: () => element(Math.random()) },
    chrome: {
      tabs: {
        query: async () => [{ id: 1, windowId: 2, title: "Test video", url }],
        create: async (tab) => openedTabs.push(tab), captureVisibleTab: async () => ""
      },
      runtime: {
        sendMessage: async (message) => { messages.push(message); return { streams }; },
        sendNativeMessage: async (_host, message) => {
          nativeMessages.push(message);
          if (!nativeAvailable) throw new Error("Native helper unavailable");
          return nativeResponse(message);
        }
      },
      storage: { onChanged: { addListener() {} }, local: { get: async () => ({}), set: async () => {} } }
    }
  });
  vm.runInContext(fs.readFileSync(`${__dirname}/popup.js`, "utf8"), context);
  await new Promise(setImmediate);
  return { elements, messages, nativeMessages, openedTabs };
}

(async () => {
  for (const buttonID of ["#send-page", "#send-youtube"]) {
    const view = await popup({ url: "https://www.youtube.com/watch?v=abc&list=RDabc&start_radio=1" });
    assert.equal(view.elements.get("#send-page").disabled, false, "YouTube does not require a captured stream");
    assert.match(view.elements.get("#send-page").textContent, /H\.265/);
    assert.equal(view.messages.some((message) => message.action === "streamsForTab"), false);
    await view.elements.get(buttonID).listeners.click();
    const message = view.nativeMessages[0];
    assert.equal(message.url, "https://www.youtube.com/watch?v=abc");
    assert.equal(message.presetID, "A1B2C3D4-E5F6-47A8-9B10-111111111111");
    assert.equal(message.start, true);
    assert.equal(message.captureKind, undefined, "YouTube must bypass anime stream probing");
  }
  const fallback = await popup({ url: "https://youtu.be/abc", nativeAvailable: false });
  await fallback.elements.get("#send-page").listeners.click();
  const link = new URL(fallback.openedTabs[0].url);
  assert.equal(link.searchParams.get("presetID"), "A1B2C3D4-E5F6-47A8-9B10-111111111111");
  assert.equal(link.searchParams.get("start"), "1");
  assert.equal(link.searchParams.has("captureKind"), false);

  const embedded = await popup({ url: "https://anime.example/watch/1", streams: [{ url: "https://cdn.example/master.m3u8", kind: "hls", label: "HLS" }] });
  await embedded.elements.get("#send-page").listeners.click();
  assert.equal(embedded.nativeMessages[0].captureKind, "hls");
  const empty = await popup({ url: "https://anime.example/watch/1" });
  assert.equal(empty.elements.get("#send-page").disabled, true);
  const music = await popup({ url: "https://www.youtube.com/watch?v=abc", nativeResponse: (message) => message.action === "findAppleMusic"
    ? { ok: false, error: "confirm_match", title: "Song", artist: "Artist", url: "https://music.apple.com/ca/album/1" }
    : { ok: true } });
  await music.elements.get("#apple-music").listeners.click();
  assert.equal(music.elements.get("#confirm-apple-music").hidden, false);
  assert.match(music.elements.get("#confirm-apple-music").textContent, /Song.*Artist/);
  assert.equal(music.nativeMessages.length, 1, "An uncertain match must not open without confirmation");
  await music.elements.get("#confirm-apple-music").listeners.click();
  assert.equal(music.nativeMessages[1].action, "openAppleMusicMatch");
  assert.equal(music.nativeMessages[1].url, "https://music.apple.com/ca/album/1");
  console.log("Popup YouTube, native fallback, and embedded stream checks passed.");
})().catch((error) => { console.error(error); process.exitCode = 1; });
