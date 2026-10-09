(function (root) {
  function webURL(value, base) {
    const url = new URL(value, base);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error("Use an HTTP or HTTPS video link.");
    return url.href;
  }

  function attributes(line) {
    const values = {};
    for (const match of line.matchAll(/([A-Z0-9-]+)=("[^"]*"|[^,]*)/g)) values[match[1]] = match[2].replace(/^"|"$/g, "");
    return values;
  }

  function byteRange(value, previous, url) {
    const match = /^(\d+)(?:@(\d+))?$/.exec(value);
    if (!match) throw new Error("The playlist contains an invalid byte range.");
    const length = Number(match[1]);
    const start = match[2] !== undefined ? Number(match[2]) : previous?.url === url ? previous.end + 1 : NaN;
    if (!Number.isSafeInteger(length) || length <= 0 || !Number.isSafeInteger(start) || start < 0 || !Number.isSafeInteger(start + length))
      throw new Error("The playlist contains an invalid or ambiguous byte range.");
    return { start, end: start + length - 1, url };
  }

  function parsePlaylist(text, base) {
    const lines = text.replace(/^\uFEFF/, "").split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    if (lines[0] !== "#EXTM3U") throw new Error("This link did not return an HLS playlist. Try a detected video link.");
    const variants = [], media = [], segments = [];
    let pendingVariant, duration, sequence = 0, key = null, map = null, pendingRange, previousRange;
    let ended = false;
    for (const line of lines.slice(1)) {
      if (line.startsWith("#EXT-X-STREAM-INF:")) pendingVariant = attributes(line);
      else if (line.startsWith("#EXT-X-MEDIA:")) media.push(attributes(line));
      else if (line.startsWith("#EXT-X-MEDIA-SEQUENCE:")) {
        sequence = Number(line.split(":")[1]);
        if (!Number.isSafeInteger(sequence) || sequence < 0) throw new Error("Invalid HLS sequence number.");
      } else if (line.startsWith("#EXTINF:")) {
        duration = Number(line.slice(8).split(",")[0]);
        if (!Number.isFinite(duration) || duration < 0) throw new Error("Invalid HLS segment duration.");
      } else if (line.startsWith("#EXT-X-BYTERANGE:")) pendingRange = line.slice(17);
      else if (line.startsWith("#EXT-X-KEY:") || line.startsWith("#EXT-X-SESSION-KEY:")) {
        const a = attributes(line);
        if (a.METHOD === "NONE") key = null;
        else if (a.METHOD === "AES-128" && (!a.KEYFORMAT || a.KEYFORMAT === "identity") && a.URI) {
          if (a.IV && !/^0x[0-9a-f]{1,32}$/i.test(a.IV)) throw new Error("Invalid HLS encryption IV.");
          key = { url: webURL(a.URI, base), iv: a.IV || null };
        } else throw new Error("This stream uses encryption this version cannot save.");
      } else if (line.startsWith("#EXT-X-MAP:")) {
        const a = attributes(line);
        if (!a.URI) throw new Error("Missing HLS initialization file.");
        if (key && !key.iv) throw new Error("An encrypted initialization file needs an explicit IV.");
        const url = webURL(a.URI, base);
        map = { url, range: a.BYTERANGE ? byteRange(a.BYTERANGE, { url, end: -1 }, url) : null, key, sequence: 0 };
      } else if (line === "#EXT-X-DISCONTINUITY") throw new Error("This stream changes timeline or codecs. This version cannot safely merge it.");
      else if (line === "#EXT-X-ENDLIST") ended = true;
      else if (!line.startsWith("#")) {
        const url = webURL(line, base);
        if (pendingVariant) {
          const bandwidth = Number(pendingVariant.BANDWIDTH) || 0;
          variants.push({ url, bandwidth, label: pendingVariant.RESOLUTION || `${Math.round(bandwidth / 1000)} kbps`, audioGroup: pendingVariant.AUDIO || "" });
          pendingVariant = null;
        } else {
          if (duration === undefined) throw new Error("A playlist segment is missing its duration.");
          const range = pendingRange ? byteRange(pendingRange, previousRange, url) : null;
          segments.push({ url, duration, sequence, range, key, map });
          sequence++; duration = undefined; pendingRange = null; previousRange = range;
        }
      }
    }
    if (pendingVariant || duration !== undefined) throw new Error("The playlist is incomplete.");
    if (variants.length) return { variants: variants.sort((a, b) => b.bandwidth - a.bandwidth), media, segments: [] };
    if (!ended) throw new Error("This is a live or unfinished playlist. This version saves completed videos.");
    if (!segments.length) throw new Error("No video segments were found.");
    const initialMap = JSON.stringify(segments[0].map);
    if (segments.some(segment => JSON.stringify(segment.map) !== initialMap)) throw new Error("This stream changes its initialization file. It cannot be merged safely yet.");
    return { variants: [], media, segments, duration: segments.reduce((total, segment) => total + segment.duration, 0) };
  }

  function ivBytes(key, sequence) {
    const hex = key.iv ? key.iv.slice(2).padStart(32, "0") : BigInt(sequence).toString(16).padStart(32, "0");
    return Uint8Array.from(hex.match(/../g), part => parseInt(part, 16));
  }

  function cancelled(signal) { if (signal?.aborted) throw new DOMException("Download cancelled.", "AbortError"); }

  async function retry(work, signal) {
    for (let attempt = 0; ; attempt++) {
      cancelled(signal);
      try { return await work(); }
      catch (error) {
        cancelled(signal);
        if (attempt >= 2 || error.noRetry) throw error;
        await new Promise((resolve, reject) => {
          const done = () => { clearTimeout(timer); signal?.removeEventListener("abort", abort); };
          const abort = () => { done(); reject(new DOMException("Download cancelled.", "AbortError")); };
          const timer = setTimeout(() => { done(); resolve(); }, 250 * (attempt + 1));
          signal?.addEventListener("abort", abort, { once: true });
        });
      }
    }
  }

  function httpError(response) {
    const message = [401, 403].includes(response.status) ? "Access was denied. Try Use site login, or capture a fresh link."
      : `The server returned HTTP ${response.status}.`;
    const error = new Error(message);
    error.noRetry = response.status >= 400 && response.status < 500 && ![408, 429].includes(response.status);
    return error;
  }

  async function fetchResponse(url, options, range) {
    const signals = [AbortSignal.timeout(30000), ...(options.signal ? [options.signal] : [])];
    const response = await fetch(webURL(url), { credentials: options.useLogin ? "include" : "omit",
      signal: AbortSignal.any(signals), headers: range ? { Range: `bytes=${range.start}-${range.end}` } : {} });
    if (!response.ok) { void response.body?.cancel(); throw httpError(response); }
    return response;
  }

  async function binary(part, options) {
    return retry(async () => {
      const response = await fetchResponse(part.url, options, part.range);
      if (part.range && response.status !== 206) { await response.body?.cancel(); const error = new Error("This server did not honor a byte-range request. This stream cannot be saved safely."); error.noRetry = true; throw error; }
      if (part.range && !response.headers.get("content-range")?.startsWith(`bytes ${part.range.start}-${part.range.end}/`))
        throw new Error("The server returned a different byte range than requested.");
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (!bytes.length || (part.range && bytes.length !== part.range.end - part.range.start + 1)) throw new Error("A video segment was incomplete.");
      return bytes;
    }, options.signal);
  }

  async function playlist(url, options) {
    return retry(async () => {
      const response = await fetchResponse(url, options);
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let text = "", size = 0;
      try {
        for (;;) {
          const { value, done } = await reader.read(); if (done) break;
          size += value.length;
          if (size > 10 * 1024 * 1024) { const error = new Error("The playlist is too large to parse safely."); error.noRetry = true; throw error; }
          text += decoder.decode(value, { stream: true });
        }
        text += decoder.decode();
        return parsePlaylist(text, response.url || url);
      } finally { await reader.cancel().catch(() => {}); }
    }, options.signal);
  }

  async function inspect(request, options = {}, variantIndex = 0) {
    const url = webURL(request.url);
    if (request.kind === "dash" || new URL(url).pathname.toLowerCase().endsWith(".mpd")) throw new Error("DASH is detected, but its separate-track merger is not included in this first version.");
    if (request.kind === "direct" || /\.(mp4|webm|mov|m4v)$/i.test(new URL(url).pathname)) {
      const response = await retry(() => fetchResponse(url, options), options.signal);
      const contentType = response.headers.get("content-type") || "";
      const ext = /\.(mp4|webm|mov|m4v)$/i.exec(new URL(url).pathname)?.[1].toLowerCase()
        || (contentType.includes("webm") ? "webm" : contentType.includes("quicktime") ? "mov" : "mp4");
      const reader = response.body.getReader();
      try { const first = await reader.read(); if (first.done) throw new Error("The video file was empty."); }
      finally { await reader.cancel().catch(() => {}); }
      return { mode: "direct", url, extension: ext, variants: [] };
    }
    let parsed = await playlist(url, options);
    const variants = parsed.variants;
    let selected = variants[variantIndex];
    const visited = new Set([url]);
    while (parsed.variants.length) {
      selected = selected || parsed.variants[0];
      if (parsed.media.some(media => media.TYPE === "AUDIO" && media["GROUP-ID"] === selected.audioGroup && media.URI))
        throw new Error("This stream has a separate audio track. Its audio/video merger is not included yet; no silent video will be saved.");
      if (visited.has(selected.url)) throw new Error("The playlist points back to itself.");
      visited.add(selected.url);
      parsed = await playlist(selected.url, options); selected = null;
    }
    return { mode: "hls", url, extension: "mp4", variants, segments: parsed.segments, duration: parsed.duration };
  }

  async function save(plan, writable, options = {}, report = () => {}) {
    let bytesWritten = 0;
    const write = async bytes => { cancelled(options.signal); await writable.write(bytes); bytesWritten += bytes.length; };
    try {
      if (plan.mode === "direct") {
        const response = await retry(() => fetchResponse(plan.url, options), options.signal);
        const total = response.headers.get("content-encoding") ? 0 : Number(response.headers.get("content-length")) || 0;
        const reader = response.body.getReader();
        try {
          for (;;) { const { value, done } = await reader.read(); if (done) break; await write(value); report({ bytes: bytesWritten, percent: total ? Math.min(bytesWritten / total * 100, 99) : null }); }
        } finally { await reader.cancel().catch(() => {}); }
        if (!bytesWritten || (total && bytesWritten !== total)) throw new Error("The video file was incomplete.");
      } else {
        const keys = new Map();
        async function decrypt(part) {
          const bytes = await binary(part, options);
          if (!part.key) return bytes;
          if (!keys.has(part.key.url)) keys.set(part.key.url, (async () => {
            const raw = await binary({ url: part.key.url }, options);
            if (raw.length !== 16) throw new Error("The HLS key is not a valid AES-128 key.");
            return crypto.subtle.importKey("raw", raw, "AES-CBC", false, ["decrypt"]);
          })());
          const importedKey = await keys.get(part.key.url);
          try { return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-CBC", iv: ivBytes(part.key, part.sequence) }, importedKey, bytes)); }
          catch (error) { cancelled(options.signal); throw new Error("A video segment could not be decrypted with the provided HLS key."); }
        }
        const map = plan.segments[0].map;
        let transmuxer, firstInit, emitted = [];
        if (map) await write(await decrypt(map));
        else {
          if (!root.muxjs) throw new Error("The bundled MP4 muxer is missing.");
          transmuxer = new root.muxjs.mp4.Transmuxer({ remux: true });
          transmuxer.on("trackinfo", info => { if (!info.hasVideo) throw new Error("The video codec is unsupported, or this is an audio-only stream."); });
          transmuxer.on("data", data => {
            if (!firstInit) { firstInit = data.initSegment; emitted.push(firstInit); }
            else if (firstInit.length !== data.initSegment.length || firstInit.some((byte, index) => byte !== data.initSegment[index]))
              throw new Error("The stream changed codec configuration. It cannot be merged safely.");
            emitted.push(data.data);
          });
        }
        for (let index = 0; index < plan.segments.length; index += 4) {
          const batch = plan.segments.slice(index, index + 4);
          const buffers = await Promise.all(batch.map(decrypt));
          for (let offset = 0; offset < buffers.length; offset++) {
            if (map) await write(buffers[offset]);
            else {
              emitted = []; transmuxer.push(buffers[offset]); transmuxer.flush();
              if (!emitted.length) throw new Error("No supported audio/video data could be read from a segment.");
              for (const bytes of emitted) await write(bytes);
            }
            report({ bytes: bytesWritten, percent: (index + offset + 1) / plan.segments.length * 99, segments: index + offset + 1, totalSegments: plan.segments.length });
          }
        }
      }
      cancelled(options.signal);
      await writable.close(); report({ bytes: bytesWritten, percent: 100, complete: true });
      return bytesWritten;
    } catch (error) {
      await writable.abort().catch(() => {});
      throw error;
    }
  }

  root.PullrDlp = { webURL, attributes, byteRange, parsePlaylist, ivBytes, inspect, save };
})(globalThis);
