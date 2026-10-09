const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const stored = {};
const listeners = {};
const event = name => ({ addListener(fn) { listeners[name] = fn; } });
const context = vm.createContext({ console, URL, URLSearchParams, Map, Promise, Date, Number,
  chrome: {
    storage: { session: {
      async get(key) { await new Promise(resolve => setImmediate(resolve)); return { [key]: stored[key] }; },
      async set(values) { Object.assign(stored, values); }, async remove(key) { delete stored[key]; }
    } },
    action: { async setBadgeText() {}, async setBadgeBackgroundColor() {} },
    webRequest: Object.fromEntries(["onSendHeaders", "onHeadersReceived", "onBeforeRequest", "onErrorOccurred"].map(name => [name, event(name)])),
    runtime: { onMessage: event("onMessage"), getURL: file => 'chrome-extension://fixture/' + file },
    tabs: { onRemoved: event("onRemoved"), onUpdated: event("onUpdated") }
  }
});
context.importScripts = name => vm.runInContext(fs.readFileSync(path.join(__dirname, name), "utf8"), context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "background.js"), "utf8"), context);
const run = code => vm.runInContext(code, context);

(async () => {
  await run(`Promise.all([
    record({tabId: 7, url: 'https://cdn.example.com/master.m3u8?token=old', manifestRole: 'master'}),
    record({tabId: 7, url: 'https://cdn.example.com/video.mp4'}),
    record({tabId: 7, url: 'https://cdn.example.com/live', responseHeaders: [{name:'Content-Type', value:'application/dash+xml'}]})
  ])`);
  assert.equal(stored["streams:7"].length, 3, "Concurrent network and frame reports must all survive");
  listeners.onSendHeaders({ requestId: "r1", requestHeaders: [
    { name: "Referer", value: "https://player.example.com/episode" }, { name: "Origin", value: "https://player.example.com" },
    { name: "User-Agent", value: "Test browser" }, { name: "Cookie", value: "must-not-store=secret" }
  ] });
  await run(`record({tabId:7, requestId:'r1', url:'https://cdn.example.com/master.m3u8?token=new'})`);
  assert.equal(stored["streams:7"].length, 3, "Expiring tokens update the existing stream");
  const master = stored["streams:7"].find(s => s.kind === "hls");
  assert.equal(master.referrer, "https://player.example.com/episode");
  assert.equal(master.manifestRole, "master", "A later header event must keep the known master role");
  assert(!JSON.stringify(stored).includes("must-not-store"), "Passive capture must not store cookies");
  await run(`record({tabId:8, url:'https://elsewhere.example.com/video.webm'})`);
  listeners.onUpdated(7, { status: "loading" });
  await run(`forTab(7, () => Promise.resolve())`);
  assert.equal(stored["streams:7"], undefined, "Navigation clears old captures");
  assert.equal(stored["streams:8"].length, 1, "Other tabs remain intact");
  listeners.onRemoved(8); await run(`forTab(8, () => Promise.resolve())`);
  assert.equal(stored["streams:8"], undefined);
  const sender = id => ({ tab: { id }, url: 'chrome-extension://fixture/download.html?id=test' });
  const message = (action, id) => new Promise(resolve => listeners.onMessage({ action, title: 'Fixture video' }, sender(id), resolve));
  await Promise.all([message('joinDownloadQueue', 20), message('joinDownloadQueue', 21)]);
  assert.deepEqual(Array.from(stored.downloadQueue, job => job.tabId), [20, 21]);
  await message('joinDownloadQueue', 20);
  assert.equal(stored.downloadQueue.length, 2, 'Joining twice does not duplicate a job');
  assert.equal(listeners.onMessage({action:'joinDownloadQueue'}, {tab:{id:22},url:'https://example.com/'}, ()=>{}), undefined, 'Webpage scripts cannot control the queue');
  await message('leaveDownloadQueue', 20);
  assert.equal(stored.downloadQueue[0].tabId, 21, 'Finishing releases the next job');
  listeners.onRemoved(21); await run(`forTab('downloadQueue', () => Promise.resolve())`);
  assert.equal(stored.downloadQueue.length, 0, 'Closing a download tab releases its queue slot');
  await message('joinDownloadQueue', 23);
  listeners.onUpdated(23, {status:'loading'}); await run(`forTab('downloadQueue', () => Promise.resolve())`);
  assert.equal(stored.downloadQueue.length, 0, 'Reloading a download tab releases its queue slot');
  console.log("Background checks passed: capture isolation, token refresh, queue ordering, deduplication, trusted-sender checks, close/reload cleanup.");
})().catch(error => { console.error(error); process.exitCode = 1; });
