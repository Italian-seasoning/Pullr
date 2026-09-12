const assert = require("node:assert/strict");

require("./website-tracker.js");

const { activityForTab, completedSegment, isTrackingEnabled } = globalThis.PullrWebsiteTracker;

assert.deepEqual(activityForTab({ url: "https://news.ycombinator.com/item?id=1", title: "Story" }, true), {
  site: "news.ycombinator.com",
  title: "Story",
  url: "https://news.ycombinator.com/",
  isYouTube: false
});
assert.deepEqual(activityForTab({ url: "https://www.youtube.com/watch?v=abc", title: "Video - YouTube" }, true), {
  site: "youtube.com",
  title: "Video",
  url: "https://www.youtube.com/watch?v=abc",
  isYouTube: true
});
assert.equal(activityForTab({ url: "https://www.youtube.com/watch?v=abc" }, false), null);
assert.equal(activityForTab({ url: "chrome://extensions" }, true), null);
assert.equal(completedSegment({ site: "youtube.com", startedAt: 1_000 }, 31_000).seconds, 30);
assert.equal(completedSegment({ site: "youtube.com", startedAt: 1_000 }, 181_000), null);
assert.equal(isTrackingEnabled({}), false);
assert.equal(isTrackingEnabled({ hoursTrackingEnabled: false }), false);
assert.equal(isTrackingEnabled({ hoursTrackingEnabled: true }), true);

console.log("Website tracker checks passed.");
