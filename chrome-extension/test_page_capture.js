const assert = require("node:assert/strict");

const messages = [];
const documentListeners = {};
globalThis.window = globalThis;
globalThis.location = { href: "https://player.example.com/embed/1" };
globalThis.postMessage = (message) => messages.push(message);
globalThis.HTMLMediaElement = class {};
globalThis.HTMLVideoElement = class extends globalThis.HTMLMediaElement {};
globalThis.HTMLSourceElement = class {};
globalThis.Element = class {};
const video = new globalThis.HTMLVideoElement();
video.src = "https://cdn.example.com/episode.mp4";
video.currentSrc = video.src;
video.poster = "https://images.example.com/episode-1.jpg";
video.paused = true;
video.ended = false;
video.seeking = false;
video.readyState = 4;
globalThis.document = {
  documentElement: {},
  querySelectorAll: (selector) => selector === "video" || selector.includes("video[src]") ? [video] : [],
  addEventListener: (name, handler) => { documentListeners[name] = handler; }
};
globalThis.MutationObserver = class { observe() {} };
globalThis.fetch = async (url) => ({
  url,
  headers: { get: () => "application/vnd.apple.mpegurl" },
  clone: () => ({ text: async () => "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720\nvideo.m3u8" })
});
require("./page-capture.js");

const playbackMessages = () => messages.filter((message) => message.source === "pullr-playback");
assert.deepEqual(playbackMessages(), [], "Stream capture must not publish retired playback notifications at startup");
for (const type of ["playing", "waiting", "seeking", "seeked", "pause", "ended"]) {
  documentListeners[type]?.({ type, target: video });
}
assert.deepEqual(playbackMessages(), [], "Media events must not publish retired playback notifications");

let bridgeMessage;
const forwarded = [];
globalThis.addEventListener = (name, listener) => { if (name === "message") bridgeMessage = listener; };
globalThis.chrome = { runtime: { sendMessage: message => { forwarded.push(message); return Promise.resolve(); } } };
require("./content-bridge.js");
bridgeMessage({ source: window, data: { source: "pullr-playback", playing: true } });
assert.deepEqual(forwarded, [], "Old page playback messages must not wake the background worker");
bridgeMessage({ source: {}, data: { source: "pullr-page-capture", url: video.src } });
bridgeMessage({ source: window, data: { source: "pullr-page-capture", url: "file:///private/stream.mp4" } });
assert.deepEqual(forwarded, [], "The stream bridge must retain source and protocol validation");
bridgeMessage({ source: window, data: { source: "pullr-page-capture", url: video.src } });
assert.equal(forwarded.length, 1);
assert.equal(forwarded[0].action, "recordPageStream");
assert.equal(forwarded[0].url, video.src, "Valid captured streams must still reach the background worker");

(async () => {
  await globalThis.fetch("https://cdn.example.com/api/manifest?id=1");
  const captureMessages = messages.filter((message) => message.source === "pullr-page-capture");
  assert.deepEqual(captureMessages[0], {
    source: "pullr-page-capture",
    url: "https://cdn.example.com/episode.mp4",
    contentType: "",
    posterURL: "https://images.example.com/episode-1.jpg"
  });
  assert.deepEqual(captureMessages[1], {
    source: "pullr-page-capture",
    url: "https://cdn.example.com/api/manifest?id=1",
    contentType: "application/vnd.apple.mpegurl",
    posterURL: "https://images.example.com/episode-1.jpg"
  });
  await new Promise(setImmediate);
  assert.equal(captureMessages[2].manifestRole, "master");
  console.log("Page capture checks passed.");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
