const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { performance } = require("node:perf_hooks");

function background({ enabled = true, allowed = ["example.com"], idle = "active", focused = true, initialNow = 1_000, savedSession = {}, startupAlarm = false } = {}) {
  let now = initialNow;
  let sequence = 0;
  const counts = { alarmTicks: 0, localReads: 0, localWrites: 0, sessionReads: 0, sessionWrites: 0, sessionRemoves: 0, idleQueries: 0, windowQueries: 0, tabQueries: 0, nativeSends: 0 };
  const local = { hoursTrackingEnabled: enabled, allowedSites: allowed };
  const session = structuredClone(savedSession);
  const alarms = new Map();
  const sent = [];
  const state = { idle, focused, tab: { id: 1, url: "https://example.com/", title: "Example" }, nativeAvailable: true };
  const event = () => ({ listeners: [], addListener(callback) { this.listeners.push(callback); }, emit(...args) { return Promise.all(this.listeners.map(callback => callback(...args))); } });
  const storage = (data, prefix) => ({
    async get(keys) { counts[`${prefix}Reads`]++; return structuredClone(Object.fromEntries((Array.isArray(keys) ? keys : [keys]).map(key => [key, data[key]]))); },
    async set(values) { counts[`${prefix}Writes`]++; Object.assign(data, structuredClone(values)); },
    async remove(keys) { counts[`${prefix}Removes`]++; for (const key of Array.isArray(keys) ? keys : [keys]) delete data[key]; }
  });
  const chrome = {
    storage: { local: storage(local, "local"), session: storage(session, "session"), onChanged: event() },
    idle: { queryState: async () => { counts.idleQueries++; return state.idle; }, onStateChanged: event() },
    windows: { getLastFocused: async () => { counts.windowQueries++; return { id: 1, focused: state.focused }; }, onFocusChanged: event() },
    tabs: { query: async () => { counts.tabQueries++; return [state.tab]; }, onRemoved: event(), onUpdated: event(), onActivated: event() },
    alarms: { create: async (name, options) => alarms.set(name, options), clear: async name => alarms.delete(name), onAlarm: event() },
    runtime: { onMessage: event(), sendNativeMessage: async (_name, message) => { counts.nativeSends++; if (!state.nativeAvailable) throw Error("offline"); sent.push(structuredClone(message)); return { ok: true }; } },
    action: { setBadgeBackgroundColor: async () => {}, setBadgeText: async () => {}, setTitle: async () => {} },
    webRequest: { onHeadersReceived: event(), onSendHeaders: event(), onErrorOccurred: event(), onBeforeRequest: event() }
  };
  const context = vm.createContext({ chrome, URL, crypto: { randomUUID: () => `segment-${++sequence}` }, Date: class extends Date { static now() { return now; } }, console });
  context.importScripts = (...files) => files.forEach(file => vm.runInContext(fs.readFileSync(path.join(__dirname, file), "utf8"), context));
  vm.runInContext(fs.readFileSync(path.join(__dirname, "background.js"), "utf8"), context);
  if (startupAlarm) void chrome.alarms.onAlarm.emit({ name: "websiteActivity" });
  const drain = async () => { await new Promise(setImmediate); await vm.runInContext("activityRefresh", context); };
  return { counts, local, session, state, alarms, chrome, sent, drain,
    async tick(seconds = 30) { now += seconds * 1_000; if (alarms.has("websiteActivity")) { counts.alarmTicks++; await chrome.alarms.onAlarm.emit({ name: "websiteActivity" }); } await drain(); },
    async activate(seconds = 0) { now += seconds * 1_000; await chrome.tabs.onActivated.emit({ tabId: state.tab.id }); await drain(); },
    async configure(enabled) { local.hoursTrackingEnabled = enabled; await chrome.storage.onChanged.emit({ hoursTrackingEnabled: { newValue: enabled } }, "local"); await drain(); }
  };
}

async function profile() {
  for (const [name, options] of [["disabled", { enabled: false }], ["idle", { idle: "idle" }], ["ineligible", { allowed: [] }], ["active", {}]]) {
    const instance = background(options);
    await instance.drain();
    for (const key of Object.keys(instance.counts)) instance.counts[key] = 0;
    const start = performance.now();
    for (let tick = 0; tick < 120; tick++) await instance.tick();
    for (let event = 0; event < 100; event++) await instance.activate();
    console.log(JSON.stringify({ workload: name, simulatedMinutes: 60, duplicateEvents: 100, elapsedMs: +(performance.now() - start).toFixed(3), ...instance.counts }));
  }
}

async function checks() {
  const previousWorker = background();
  await previousWorker.drain();
  const restarted = background({ savedSession: previousWorker.session, initialNow: 31_000, startupAlarm: true });
  await restarted.drain();
  assert.equal(restarted.sent.length, 1, "An alarm waking a fresh MV3 worker must checkpoint persisted activity");
  assert.equal(restarted.sent[0].seconds, 30);

  const disabled = background({ enabled: false });
  await disabled.drain();
  const before = { ...disabled.counts };
  await disabled.activate();
  assert.deepEqual(disabled.counts, before, "Tracking disabled must not query or write storage on activity events");
  await disabled.chrome.runtime.onMessage.emit({ action: "videoPlaybackState", playing: true }, { tab: { id: 1 }, frameId: 0 }, () => {});
  await disabled.drain();
  assert.deepEqual(disabled.counts, before, "Playback notifications must not persist unused tracking state while disabled");
  assert.equal(disabled.alarms.size, 0);

  for (const options of [{ idle: "idle" }, { focused: false }, { allowed: [] }]) {
    const instance = background(options);
    await instance.drain();
    assert.equal(instance.alarms.size, 0, "Idle, unfocused, and ineligible sites must not retain an activity alarm");
    await instance.tick();
    assert.equal(instance.counts.nativeSends, 0);
  }

  const active = background();
  await active.drain();
  assert.equal(active.alarms.size, 1);
  await active.activate(10);
  assert.equal(active.sent.length, 0, "Duplicate events must preserve the current checkpoint instead of sending tiny segments");
  await active.tick(20);
  assert.equal(active.sent[0].seconds, 30);
  active.state.idle = "idle";
  await active.activate(5);
  assert.equal(active.sent[1].seconds, 5);
  assert.equal(active.alarms.size, 0);
  active.state.idle = "active";
  await active.activate();
  await active.activate(5);
  const sentBeforeDisable = active.sent.length;
  await active.configure(false);
  assert.equal(active.sent.length, sentBeforeDisable + 1, "Disabling must send the final active segment");
  assert.equal(active.sent.at(-1).seconds, 5, "Disabling must flush elapsed time since the last checkpoint");
  assert.equal(active.session.websiteActivity, undefined);

  const removedSite = background();
  await removedSite.drain();
  await removedSite.activate(5);
  removedSite.local.allowedSites = [];
  await removedSite.chrome.storage.onChanged.emit({ allowedSites: { newValue: [] } }, "local");
  await removedSite.drain();
  assert.equal(removedSite.sent[0]?.seconds, 5, "Removing the active allowed site must flush time accrued before removal");
  assert.equal(removedSite.alarms.size, 0);

  const retry = background();
  await retry.drain();
  retry.state.nativeAvailable = false;
  await retry.tick();
  const pending = structuredClone(retry.local.activityOutbox[0]);
  assert.equal(pending.seconds, 30);
  retry.state.idle = "idle";
  await retry.activate(10);
  assert.equal(retry.alarms.size, 1, "Pending activity must retry even while the Mac is idle");
  retry.state.nativeAvailable = true;
  await retry.tick();
  assert.deepEqual(retry.sent[0], pending, "Idle retries must retain the original event");
  assert.equal(retry.alarms.size, 0, "Stop idle retries once the outbox drains");
  retry.state.idle = "active";
  await retry.activate(10);
  assert.deepEqual(retry.sent[0], pending, "Retry must retain the exact event ID and original timestamp");
  assert.equal(retry.local.activityOutbox.length, 0);
  console.log("Background tracking checks passed.");
}

(process.argv.includes("--profile") ? profile() : checks()).catch(error => { console.error(error); process.exitCode = 1; });
