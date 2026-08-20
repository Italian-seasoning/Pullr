const assert = require("node:assert/strict");

const messages = [];
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
globalThis.document = {
  documentElement: {},
  querySelectorAll: (selector) => selector === "video" || selector.includes("video[src]") ? [video] : []
};
globalThis.MutationObserver = class { observe() {} };
globalThis.fetch = async (url) => ({
  url,
  headers: { get: () => "application/vnd.apple.mpegurl" },
  clone: () => ({ text: async () => "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720\nvideo.m3u8" })
});
require("./page-capture.js");

(async () => {
  await globalThis.fetch("https://cdn.example.com/api/manifest?id=1");
  assert.deepEqual(messages[0], {
    source: "pullr-page-capture",
    url: "https://cdn.example.com/episode.mp4",
    contentType: "",
    posterURL: "https://images.example.com/episode-1.jpg"
  });
  assert.deepEqual(messages[1], {
    source: "pullr-page-capture",
    url: "https://cdn.example.com/api/manifest?id=1",
    contentType: "application/vnd.apple.mpegurl",
    posterURL: "https://images.example.com/episode-1.jpg"
  });
  await new Promise(setImmediate);
  assert.equal(messages[2].manifestRole, "master");
  console.log("Page capture checks passed.");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
