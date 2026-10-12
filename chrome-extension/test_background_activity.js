const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function background(local = {}) {
  const session = {};
  const alarms = new Map();
  const received = [];
  let available = false;
  let now = 1_000_000;
  let tabQueries = 0;
  let acknowledgement = null;
  const event = () => ({ addListener(fn) { this.listener = fn; } });
  const storage = data => ({
    async get(keys) {
      return Object.fromEntries((Array.isArray(keys) ? keys : [keys])
        .map(key => [key, structuredClone(data[key])]));
    },
    async set(value) { Object.assign(data, structuredClone(value)); },
    async remove(keys) { for (const key of [keys].flat()) delete data[key]; }
  });
  const chrome = {
    storage: { local: storage(local), session: storage(session), onChanged: event() },
    alarms: {
      async create(name, options) { alarms.set(name, options); },
      async clear(name) { return alarms.delete(name); },
      onAlarm: event()
    },
    idle: { async queryState() { return 'active'; }, onStateChanged: event() },
    windows: {
      async getLastFocused() { return { id: 1, focused: true }; },
      onFocusChanged: event()
    },
    tabs: {
      async query() {
        tabQueries++;
        return [{ id: 1, url: 'https://example.com/page', title: 'Example' }];
      },
      onRemoved: event(), onUpdated: event(), onActivated: event()
    },
    runtime: {
      async sendNativeMessage(host, message) {
        assert.equal(host, 'app.pullr.native');
        if (!available) throw Error('helper unavailable');
        received.push(structuredClone(message));
        if (acknowledgement) await acknowledgement;
        return { ok: true };
      },
      onMessage: event()
    },
    webRequest: {
      onHeadersReceived: event(), onSendHeaders: event(),
      onErrorOccurred: event(), onBeforeRequest: event()
    }
  };
  const context = vm.createContext({
    chrome, URL, Date: { now: () => now }, crypto: { randomUUID: () => 'captured-id' }
  });
  context.importScripts = (...files) => files.forEach(file =>
    vm.runInContext(fs.readFileSync(path.join(__dirname, file), 'utf8'), context));
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'background.js'), 'utf8'), context);
  const settle = async () => {
    // Let Chrome event callbacks and the serialized refresh promise finish.
    await new Promise(resolve => setImmediate(resolve));
    await vm.runInContext('activityRefresh', context);
  };
  return {
    local, session, alarms, received, settle,
    recover() { available = true; },
    holdAcknowledgement() {
      let release;
      acknowledgement = new Promise(resolve => { release = resolve; });
      return () => { acknowledgement = null; release(); };
    },
    enable() {
      local.hoursTrackingEnabled = true;
      chrome.storage.onChanged.listener({ hoursTrackingEnabled: { newValue: true } }, 'local');
    },
    async tick() {
      now += 30_000;
      for (const name of [...alarms.keys()]) chrome.alarms.onAlarm.listener({ name });
      await settle();
    },
    async disable() {
      local.hoursTrackingEnabled = false;
      chrome.storage.onChanged.listener({ hoursTrackingEnabled: { newValue: false } }, 'local');
      await settle();
    },
    get tabQueries() { return tabQueries; }
  };
}

(async () => {
  const app = background({ hoursTrackingEnabled: true, allowedSites: ['example.com'] });
  await app.settle();
  await app.tick();
  const captured = structuredClone(app.local.activityOutbox);
  assert.equal(captured.length, 1);
  assert.equal(captured[0].recordedAt, 1030);
  assert.equal(captured[0].seconds, 30);
  await app.disable();
  assert.deepEqual(app.local.activityOutbox, captured, 'disabling must retain captured activity');
  const queriesBeforeRecovery = app.tabQueries;
  app.recover();
  await app.tick();
  assert.deepEqual(app.received, captured, 'alarm must deliver saved activity after helper recovery');
  assert.deepEqual(app.local.activityOutbox, []);
  assert.equal(app.local.websiteTrackingSync, 'saved');
  assert.equal(app.tabQueries, queriesBeforeRecovery, 'disabled retries must not capture new activity');
  assert.equal(app.session.websiteActivity, undefined);
  await app.tick();
  assert.deepEqual(app.received, captured, 'acknowledged records must not be sent again');
  assert.equal(app.alarms.size, 0, 'stop retries once the disabled outbox drains');

  const restarted = background({ hoursTrackingEnabled: false, activityOutbox: captured });
  await restarted.settle();
  assert.deepEqual(restarted.local.activityOutbox, captured);
  restarted.recover();
  await restarted.tick();
  assert.deepEqual(restarted.received, captured, 'restart must restore retries while tracking is disabled');
  assert.equal(restarted.tabQueries, 0);
  assert.equal(restarted.alarms.size, 0);

  const toggled = background({ hoursTrackingEnabled: false, allowedSites: ['example.com'], activityOutbox: captured });
  await toggled.settle();
  toggled.recover();
  const acknowledge = toggled.holdAcknowledgement();
  const retry = toggled.tick();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(toggled.received.length, 1);
  toggled.enable();
  await new Promise(resolve => setImmediate(resolve));
  acknowledge();
  await retry;
  await toggled.settle();
  assert.equal(toggled.alarms.size, 1, 'enabling during retry must retain the recording alarm');
  await toggled.tick();
  assert.equal(toggled.received.length, 2, 'recording must continue after enabling during retry');

  const empty = background({ hoursTrackingEnabled: false });
  await empty.settle();
  assert.equal(empty.alarms.size, 0);
  assert.equal(empty.tabQueries, 0);
  console.log('Background activity retry checks passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
