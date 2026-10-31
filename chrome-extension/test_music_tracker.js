const assert = require("node:assert/strict");

require("./music-tracker.js");

const { cleanTitle, splitTitle, listenedDelta } = globalThis.PullrMusicTracker;
assert.equal(cleanTitle("Song (Official Video) - YouTube"), "Song");
assert.deepEqual(splitTitle("Artist - Song (Official Audio)"), { title: "Song", artist: "Artist" });
assert.deepEqual(splitTitle("ASTRAL! - SUPER SLOWED", "xxephyrr"), { title: "ASTRAL! - SUPER SLOWED", artist: "xxephyrr" });
assert.deepEqual(splitTitle("ASTRAL! - SUPER SLOWED"), { title: "ASTRAL! - SUPER SLOWED", artist: "" });
assert.deepEqual(splitTitle("Artist - Song", "Artist"), { title: "Song", artist: "Artist" });
assert.equal(listenedDelta(10, 12.5), 2.5);
assert.equal(listenedDelta(10, 40), 0);

console.log("Music tracker checks passed.");
