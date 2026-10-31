const assert = require('node:assert/strict');
require('./activity-outbox.js');
(async () => {
  const data = {};
  const storage = { get: async keys => Object.fromEntries((Array.isArray(keys) ? keys : [keys]).map(key => [key, structuredClone(data[key])])), set: async value => Object.assign(data, structuredClone(value)) };
  const event = {id:'test', action:'trackWebsite', seconds:30, recordedAt:1000};
  await PullrActivityOutbox.sync(storage, async () => { throw Error('helper unavailable'); }, event);
  assert.deepEqual(data.activityOutbox, [event]);
  assert.equal(data.websiteTrackingSync, 'waiting');
  const received = [];
  await PullrActivityOutbox.sync(storage, async message => { received.push(message); return {ok:true}; });
  assert.deepEqual(received, [event]);
  assert.deepEqual(data.activityOutbox, []);
  assert.equal(data.websiteTrackingSync, 'saved');
  let writes = 0;
  const measuredStorage = {
    get: async keys => Object.fromEntries((Array.isArray(keys) ? keys : [keys]).map(key => [key, structuredClone(data[key])])),
    set: async values => { writes++; Object.assign(data, structuredClone(values)); }
  };
  await PullrActivityOutbox.sync(measuredStorage, async () => { throw Error('empty outbox must not send'); });
  assert.equal(writes, 0, 'An empty, already-synced outbox must not rewrite local storage');
  data.activityOutbox = Array.from({length:2000}, (_,id) => ({id}));
  assert.equal(await PullrActivityOutbox.sync(storage, async () => ({ok:false}), event), false);
  assert.equal(data.activityOutbox.length, 2001);
  assert.equal(data.websiteTrackingSync, 'full');
  assert.equal(await PullrActivityOutbox.sync(storage, async () => ({ok:true})), true);
  assert.deepEqual(data.activityOutbox, []);
  console.log('Activity outbox checks passed.');
})();
