(function (root) {
  // ponytail: pause fresh recording at 2,000 unsynced segments until the helper recovers.
  async function sync(storage, send, segment = null) {
    const saved = await storage.get('activityOutbox');
    let pending = saved.activityOutbox || [];
    if (segment) {
      pending.push(segment);
      await storage.set({ activityOutbox: pending });
    }
    while (pending.length) {
      let response;
      try { response = await send(pending[0]); } catch { break; }
      if (!response?.ok) break;
      pending = pending.slice(1);
      await storage.set({ activityOutbox: pending });
    }
    await storage.set({ websiteTrackingSync: pending.length >= 2000 ? 'full' : pending.length ? 'waiting' : 'saved' });
    return pending.length < 2000;
  }
  root.PullrActivityOutbox = { sync };
})(typeof globalThis !== 'undefined' ? globalThis : self);
