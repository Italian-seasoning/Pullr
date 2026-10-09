const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
require("../dlp.js");
const dlp = globalThis.PullrDlp;
const box = { Uint8Array, Uint32Array, Int32Array, DataView, ArrayBuffer, console };
box.window = box;
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../vendor/mux.min.js"), "utf8"), box);
globalThis.muxjs = box.muxjs;

assert.throws(() => dlp.webURL("file:///secret"));
assert.throws(() => dlp.webURL("https://user:secret@example.com/video"));
assert.equal(dlp.webURL("part.ts?sig=a%2Bb", "https://cdn.example.com/path/master.m3u8"), "https://cdn.example.com/path/part.ts?sig=a%2Bb");
const master = dlp.parsePlaylist('#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio.m3u8",NAME="English, original"\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,AUDIO="audio"\nvideo.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\nbest.m3u8', "https://cdn.example.com/master.m3u8");
assert.equal(master.variants[0].label, "1920x1080");
assert.equal(master.media[0].NAME, "English, original");
const ranged = dlp.parsePlaylist('#EXTM3U\n#EXT-X-MAP:URI="all.mp4",BYTERANGE="100@0"\n#EXTINF:1,\n#EXT-X-BYTERANGE:50@100\nall.mp4\n#EXTINF:1,\n#EXT-X-BYTERANGE:25\nall.mp4\n#EXT-X-ENDLIST', "https://cdn.example.com/video.m3u8");
assert.deepEqual(ranged.segments[1].range, { start: 150, end: 174, url: "https://cdn.example.com/all.mp4" });
assert.throws(() => dlp.parsePlaylist('#EXTM3U\n#EXTINF:1,\n#EXT-X-BYTERANGE:20\nother.ts\n#EXT-X-ENDLIST', "https://cdn.example.com/video.m3u8"));
assert.throws(() => dlp.parsePlaylist('#EXTM3U\n#EXTINF:1,\npart.ts', "https://cdn.example.com/video.m3u8"), /live|unfinished/);
assert.throws(() => dlp.parsePlaylist('#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key"', "https://cdn.example.com/video.m3u8"), /encryption/);
assert.throws(() => dlp.parsePlaylist('#EXTM3U\n#EXT-X-DISCONTINUITY\n#EXT-X-ENDLIST', "https://cdn.example.com/video.m3u8"), /timeline/);
assert.throws(() => dlp.parsePlaylist('#EXTM3U\n#EXTINF:1,', "https://cdn.example.com/video.m3u8"), /incomplete/);
const aes = dlp.parsePlaylist('#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:257\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:1,\npart.ts\n#EXT-X-ENDLIST', "https://cdn.example.com/video.m3u8");
assert.deepEqual([...dlp.ivBytes(aes.segments[0].key, 257)].slice(-2), [1, 1]);
console.log("Parser checks passed: URL boundaries, signed links, quality selection, quoted attributes, byte ranges, AES IVs, live/protected/incomplete stream errors.");

function writer(destination) {
  const descriptor = fs.openSync(destination, "w");
  return { async write(bytes) { fs.writeSync(descriptor, bytes); }, async close() { fs.closeSync(descriptor); }, async abort() { fs.closeSync(descriptor); fs.unlinkSync(destination); } };
}

(async () => {
  if (!process.argv[2]) return;
  const folder = process.argv[2]; fs.mkdirSync(folder, { recursive: true });
  for (const [name, url, kind] of [
    ["hls", "http://127.0.0.1:8765/public/master", "hls"],
    ["fmp4", "http://127.0.0.1:8765/public/fmp4.m3u8", "hls"],
    ["aes", "http://127.0.0.1:8765/public/aes.m3u8", "hls"],
    ["direct", "http://127.0.0.1:8765/public/video.mp4", "direct"]
  ]) {
    const plan = await dlp.inspect({ url, kind });
    const output = path.join(folder, name + ".mp4");
    let completed = false;
    const bytes = await dlp.save(plan, writer(output), {}, report => { completed ||= report.complete === true; });
    assert(bytes > 1000 && completed);
    console.log(name + " real download passed · " + bytes + " bytes streamed to disk.");
  }
  const broken = await dlp.inspect({ url: "http://127.0.0.1:8765/public/broken.m3u8", kind: "hls" });
  const badFile = path.join(folder, "broken.mp4");
  await assert.rejects(() => dlp.save(broken, writer(badFile)));
  assert(!fs.existsSync(badFile));
  const stop = new AbortController(); stop.abort();
  const cancelled = path.join(folder, "cancelled.mp4");
  await assert.rejects(() => dlp.save(broken, writer(cancelled), { signal: stop.signal }), { name: "AbortError" });
  assert(!fs.existsSync(cancelled));
  console.log("Failure and cancellation passed; incomplete outputs removed by the writer.");
})().catch(error => { console.error(error); process.exitCode = 1; });
