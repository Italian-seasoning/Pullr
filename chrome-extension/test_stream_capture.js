const assert = require("node:assert/strict");

require("./stream-capture.js");

const {
  classifyStream,
  preferredStream,
  streamIdentity,
  mergeStream,
  safeRequestContext,
  responseSize,
  singleYouTubeVideoURL,
  badgeState
} = globalThis.PullrStreamCapture;

assert.equal(
  singleYouTubeVideoURL("https://www.youtube.com/watch?v=pu22yjU49Rw&list=RDR9ag38BwOP8&index=3"),
  "https://www.youtube.com/watch?v=pu22yjU49Rw"
);
assert.equal(
  singleYouTubeVideoURL("https://music.youtube.com/watch?v=abc&list=RDAMVMabc&start_radio=1"),
  "https://music.youtube.com/watch?v=abc"
);
assert.deepEqual(badgeState(12, true), { text: "ON", color: "#137333", title: "Pullr is tracking this YouTube tab" });
assert.deepEqual(badgeState(3, false), { text: "3", color: "#297aed", title: "Pullr detected 3 media streams" });

assert.equal(classifyStream("https://cdn.example.com/master.m3u8?token=1").kind, "hls");
assert.equal(
  classifyStream("https://cdn.example.com/api/manifest", [{ name: "Content-Type", value: "application/vnd.apple.mpegurl" }]).kind,
  "hls"
);
assert.equal(classifyStream("https://cdn.example.com/stream.mpd").kind, "dash");
assert.equal(classifyStream("https://cdn.example.com/video.mp4").kind, "direct");
assert.equal(
  classifyStream("https://cdn.example.com/media?id=1", [{ name: "Content-Type", value: "video/webm" }]).kind,
  "direct"
);
assert.equal(classifyStream("https://cdn.example.com/segment.m4s"), null);
assert.equal(
  classifyStream("https://cdn.example.com/segment.ts", [{ name: "Content-Type", value: "video/mp2t" }]),
  null
);
assert.equal(classifyStream("blob:https://video.example.com/123"), null);

const preferred = preferredStream([
  { url: "https://ads.example.com/trailer.mp4", kind: "direct" },
  { url: "https://video.example.com/episode.m3u8", kind: "hls" },
  { url: "https://video.example.com/older.mpd", kind: "dash" }
]);
assert.equal(preferred.url, "https://video.example.com/episode.m3u8");
assert.equal(
  preferredStream([
    { url: "https://video.example.com/index-v1-a1.m3u8", kind: "hls", manifestRole: "media" },
    { url: "https://video.example.com/master.m3u8", kind: "hls", manifestRole: "master" }
  ]).manifestRole,
  "master"
);
assert.equal(preferredStream([]), null);
assert.equal(
  preferredStream([
    { url: "https://cdn.example.com/big_buck_bunny.mp4", kind: "direct" },
    { url: "https://cdn.example.com/episode-17.mp4", kind: "direct" }
  ]).url,
  "https://cdn.example.com/episode-17.mp4"
);
assert.equal(
  streamIdentity({ url: "https://cdn.example.com/episode.mp4?token=one&quality=720", kind: "direct" }),
  streamIdentity({ url: "https://cdn.example.com/episode.mp4?token=two&quality=720", kind: "direct" })
);
const merged = mergeStream(
  [{ url: "https://cdn.example.com/episode.mp4?token=old", kind: "direct", posterURL: "https://img.example/episode.jpg", contentLength: 123 }],
  { url: "https://cdn.example.com/episode.mp4?token=new", kind: "direct", posterURL: "", contentLength: 0 }
);
assert.equal(merged.length, 1);
assert.equal(merged[0].url, "https://cdn.example.com/episode.mp4?token=new");
assert.equal(merged[0].posterURL, "https://img.example/episode.jpg");
assert.equal(merged[0].contentLength, 123);
assert.deepEqual(
  safeRequestContext([
    { name: "Referer", value: "https://video.example/watch/1" },
    { name: "Origin", value: "https://video.example" },
    { name: "User-Agent", value: "Comet Test" },
    { name: "Cookie", value: "must-not-leave-browser=1" },
    { name: "Authorization", value: "must-not-leave-browser" }
  ]),
  {
    referrer: "https://video.example/watch/1",
    origin: "https://video.example",
    userAgent: "Comet Test"
  }
);
assert.equal(responseSize([{ name: "Content-Range", value: "bytes 0-999/123456" }]), 123456);

console.log("Stream capture checks passed.");
