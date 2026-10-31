const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { performance } = require("node:perf_hooks");

require("./music-tracker.js");

const { cleanTitle, splitTitle, listenedDelta } = globalThis.PullrMusicTracker;
assert.equal(cleanTitle("Song (Official Video) - YouTube"), "Song");
assert.deepEqual(splitTitle("Artist - Song (Official Audio)"), { title: "Song", artist: "Artist" });
assert.deepEqual(splitTitle("ASTRAL! - SUPER SLOWED", "xxephyrr"), { title: "ASTRAL! - SUPER SLOWED", artist: "xxephyrr" });
assert.deepEqual(splitTitle("ASTRAL! - SUPER SLOWED"), { title: "ASTRAL! - SUPER SLOWED", artist: "" });
assert.deepEqual(splitTitle("Artist - Song", "Artist"), { title: "Song", artist: "Artist" });
assert.equal(listenedDelta(10, 12.5), 2.5);
assert.equal(listenedDelta(10, 40), 0);

const listeners = {};
const observers = [];
const intervals = [];
const messages = [];
let queries = 0;
let title = "Artist - Song";
const titleElement = { contains: target => target === titleElement };
titleElement.closest = () => titleElement;
const video = {
  currentTime: 0, paused: false, duration: 120, isConnected: true,
  addEventListener: (name, callback) => { listeners[name] = callback; },
  removeEventListener: name => { delete listeners[name]; }
};
const context = vm.createContext({
  URL, console,
  location: { href: "https://www.youtube.com/watch?v=abc" },
  chrome: { runtime: { sendMessage: async message => { messages.push(message); } } },
  document: {
    documentElement: {}, title,
    querySelector: selector => { queries++; return selector === "video" ? video : selector === "title" ? titleElement : selector.includes(".title") ? { textContent: title } : null; },
    addEventListener() {}
  },
  MutationObserver: class { constructor(callback) { this.callback = callback; observers.push(this); } observe() {} },
  setInterval: callback => intervals.push(callback),
  addEventListener() {}
});
vm.runInContext(fs.readFileSync(require.resolve("./music-tracker.js"), "utf8"), context);
messages.length = 0;
queries = 0;
const start = performance.now();
for (let update = 1; update <= 240; update++) {
  video.currentTime = update / 4;
  listeners.timeupdate?.();
  if (update % 8 === 0) intervals.forEach(callback => callback());
}
for (let mutation = 0; mutation < 100; mutation++) observers.forEach(observer => observer.callback([{ target: {} }]));
if (process.argv.includes("--profile")) {
  console.log(JSON.stringify({ workload: "60 seconds playback, 100 unrelated DOM mutations", elapsedMs: +(performance.now() - start).toFixed(3), intervals: intervals.length, queries, retiredListeningMessages: messages.filter(message => message.action === "trackListening").length }));
  process.exit(0);
}
assert.equal(intervals.length, 0, "Music metadata must not poll the page on a recurring timer");
assert.equal(queries, 0, "Playback ticks and unrelated DOM mutations must not rescan metadata or the connected video");
assert.equal(messages.length, 0, "Playback must not send retired listening events");
title = "Artist - Next Song";
observers.forEach(observer => observer.callback([{ target: titleElement }]));
assert.equal(messages.at(-1).title, "Next Song", "A title mutation must still update music metadata");
video.duration = 180;
listeners.durationchange?.();
assert.equal(messages.at(-1).duration, 180, "Metadata must update once media duration becomes available");
title = "Artist - Asynchronous Song";
const metadataElement = { closest: () => metadataElement };
observers.forEach(observer => observer.callback([{ target: { nodeType: 3, parentElement: metadataElement }, type: "characterData" }]));
assert.equal(messages.at(-1).title, "Asynchronous Song", "Metadata arriving after the page title and playback events must update without polling");

console.log("Music tracker checks passed.");
