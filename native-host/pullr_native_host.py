#!/usr/bin/env python3
import base64
import binascii
from difflib import SequenceMatcher
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from urllib.parse import urlencode, urlparse
from urllib.request import urlopen


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) != 4:
        return None

    length = struct.unpack("<I", raw_length)[0]
    if length > 1_000_000:
        return None
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))


def write_message(message):
    encoded = json.dumps(message).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def write_diagnostic(action, outcome, error=None, directory=None, now=None):
    """Write only allow-listed operational fields; stdout is reserved for Chrome."""
    try:
        root = Path(directory) if directory else Path.home() / "Library/Application Support/Pullr/Diagnostics"
        root.mkdir(parents=True, exist_ok=True)
        path = root / "native-host.jsonl"
        backup = root / "native-host.jsonl.1"
        if path.exists() and path.stat().st_size >= 2_000_000:
            os.replace(path, backup)

        timestamp = datetime.fromtimestamp(now if now is not None else time.time(), timezone.utc)
        event = {
            "timestamp": timestamp.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "action": re.sub(r"[^a-zA-Z0-9_.-]", "_", str(action))[:64],
            "outcome": re.sub(r"[^a-zA-Z0-9_.-]", "_", str(outcome))[:64],
        }
        if error is not None:
            event["error"] = type(error).__name__ if isinstance(error, BaseException) else re.sub(
                r"[^a-zA-Z0-9_.-]", "_", str(error)
            )[:80]

        payload = (json.dumps(event, separators=(",", ":")) + "\n").encode("utf-8")
        descriptor = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
        try:
            os.write(descriptor, payload)
        finally:
            os.close(descriptor)
        return True
    except (OSError, TypeError, ValueError):
        return False


def save_thumbnail(data_url, directory=None):
    prefix = "data:image/jpeg;base64,"
    if not isinstance(data_url, str) or not data_url.startswith(prefix):
        return None
    try:
        image = base64.b64decode(data_url[len(prefix):], validate=True)
    except (binascii.Error, ValueError):
        return None
    if not 4 <= len(image) <= 2_000_000 or not image.startswith(b"\xff\xd8\xff"):
        return None
    root = Path(directory) if directory else Path.home() / "Library/Application Support/Pullr/Thumbnails"
    root.mkdir(parents=True, exist_ok=True)
    path = root / f"{uuid.uuid4().hex}.jpg"
    path.write_bytes(image)
    return path.resolve().as_uri()


def build_deep_link(message, thumbnail_directory=None):
    if not isinstance(message, dict):
        return None

    url = message.get("url", "")
    if urlparse(url).scheme not in {"http", "https"}:
        return None

    params = {"url": url}
    preset_id = message.get("presetID", "")
    try:
        params["presetID"] = str(uuid.UUID(preset_id))
    except (ValueError, TypeError, AttributeError):
        pass
    if message.get("start") is True:
        params["start"] = "1"
    referrer = message.get("referrer", "")
    if urlparse(referrer).scheme in {"http", "https"}:
        params["referrer"] = referrer
    user_agent = message.get("userAgent", "")
    if isinstance(user_agent, str):
        user_agent = user_agent.replace("\r", "").replace("\n", "")[:500]
        if user_agent:
            params["userAgent"] = user_agent
    capture_kind = message.get("captureKind", "")
    if capture_kind in {"hls", "dash", "direct"}:
        params["captureKind"] = capture_kind
    origin = message.get("origin", "")
    parsed_origin = urlparse(origin)
    if parsed_origin.scheme in {"http", "https"} and parsed_origin.netloc:
        params["origin"] = f"{parsed_origin.scheme}://{parsed_origin.netloc}"
    content_type = message.get("contentType", "")
    if isinstance(content_type, str) and len(content_type) <= 200:
        params["contentType"] = content_type.replace("\r", "").replace("\n", "")
    content_length = message.get("contentLength", 0)
    if isinstance(content_length, (int, float)) and 0 < content_length < 10**13:
        params["contentLength"] = str(int(content_length))
    thumbnail_url = message.get("thumbnailURL", "")
    if urlparse(thumbnail_url).scheme in {"http", "https"}:
        params["thumbnailURL"] = thumbnail_url
    else:
        saved_thumbnail = save_thumbnail(message.get("thumbnailDataURL", ""), thumbnail_directory)
        if saved_thumbnail:
            params["thumbnailURL"] = saved_thumbnail
    return f"pullr://add?{urlencode(params)}"


def _safe_text(value, limit):
    if not isinstance(value, str):
        return ""
    return value.replace("\r", " ").replace("\n", " ").strip()[:limit]


def save_listening_event(message, directory=None, now=None):
    url = _safe_text(message.get("url"), 2_000)
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or not (host == "youtu.be" or host.endswith("youtube.com")):
        return None

    try:
        seconds = float(message.get("seconds", 0))
    except (TypeError, ValueError):
        return None
    if not 0 < seconds <= 60:
        return None

    title = _safe_text(message.get("title"), 240)
    if not title:
        return None

    event = {
        "id": str(uuid.uuid4()),
        "title": title,
        "artist": _safe_text(message.get("artist"), 160),
        "url": url,
        "videoID": _safe_text(message.get("videoID"), 32),
        "seconds": round(seconds, 3),
        "listenedAt": float(now if now is not None else time.time()),
    }
    root = Path(directory) if directory else Path.home() / "Library/Application Support/Pullr"
    root.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    descriptor = os.open(root / "listening-history.jsonl", os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, payload)
    finally:
        os.close(descriptor)
    return event


def _normalized_music_text(value):
    value = _safe_text(value, 240).lower()
    value = re.sub(r"[\[(](official (music )?video|official audio|lyrics?|lyric video|hd|4k)[^\])]*[\])]", " ", value)
    return " ".join(re.findall(r"[a-z0-9]+", value))


def split_music_title(title, artist=""):
    clean_title = _safe_text(title, 240).removesuffix(" - YouTube").strip()
    clean_artist = _safe_text(artist, 160).removesuffix(" - Topic").strip()
    if " - " in clean_title:
        possible_artist, possible_title = clean_title.split(" - ", 1)
        if possible_artist and possible_title:
            clean_title = possible_title
            if not clean_artist:
                clean_artist = possible_artist
    return clean_title, clean_artist


def best_music_match(title, artist, results):
    title, artist = split_music_title(title, artist)
    wanted_title = _normalized_music_text(title)
    wanted_artist = _normalized_music_text(artist)
    if not wanted_title:
        return None

    def score(candidate):
        title_score = SequenceMatcher(None, wanted_title, _normalized_music_text(candidate.get("trackName", ""))).ratio()
        if not wanted_artist:
            return title_score
        artist_score = SequenceMatcher(None, wanted_artist, _normalized_music_text(candidate.get("artistName", ""))).ratio()
        return title_score * 0.75 + artist_score * 0.25

    candidates = [item for item in results if isinstance(item, dict) and item.get("trackViewUrl")]
    match = max(candidates, key=score, default=None)
    return match if match and score(match) >= 0.58 else None


def find_apple_music(message, fetcher=None):
    title, artist = split_music_title(message.get("title", ""), message.get("artist", ""))
    if not title:
        return None
    terms = [" ".join(part for part in [artist, title] if part)]
    if artist:
        terms.append(title)

    for term in terms:
        endpoint = "https://itunes.apple.com/search?" + urlencode({
            "term": term,
            "country": "CA",
            "media": "music",
            "entity": "song",
            "limit": 20,
        })
        if fetcher is None:
            with urlopen(endpoint, timeout=8) as response:
                payload = json.load(response)
        else:
            payload = fetcher(endpoint)
        match = best_music_match(title, artist, payload.get("results", []))
        if match:
            return match
    return None


def main():
    message = read_message()
    if not isinstance(message, dict):
        write_diagnostic("message", "invalid")
        write_message({"ok": False, "error": "invalid_message"})
        return

    action = message.get("action", "add")
    if action == "trackListening":
        event = save_listening_event(message)
        write_diagnostic("trackListening", "success" if event else "invalid")
        write_message({"ok": bool(event)})
        return

    if action == "findAppleMusic":
        try:
            match = find_apple_music(message)
        except Exception as error:
            write_diagnostic("findAppleMusic", "lookup_failed", error)
            write_message({"ok": False, "error": "lookup_failed"})
            return
        if not match:
            write_diagnostic("findAppleMusic", "no_match")
            write_message({"ok": False, "error": "no_match"})
            return
        try:
            opened = subprocess.run(
                ["open", "-a", "Music", match["trackViewUrl"]],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except OSError as error:
            write_diagnostic("findAppleMusic", "open_failed", error)
            write_message({"ok": False, "error": "open_failed"})
            return
        if opened.returncode != 0:
            write_diagnostic("findAppleMusic", "open_failed", f"exit_{opened.returncode}")
            write_message({"ok": False, "error": "open_failed"})
            return
        write_diagnostic("findAppleMusic", "success")
        write_message({
            "ok": True,
            "title": match.get("trackName", ""),
            "artist": match.get("artistName", ""),
            "url": match["trackViewUrl"],
        })
        return

    deep_link = build_deep_link(message)

    if not deep_link:
        write_diagnostic("add", "invalid")
        write_message({"ok": False, "error": "missing_url"})
        return

    try:
        opened = subprocess.run(
            ["open", deep_link],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError as error:
        write_diagnostic("add", "open_failed", error)
        write_message({"ok": False, "error": "open_failed"})
        return
    if opened.returncode != 0:
        write_diagnostic("add", "open_failed", f"exit_{opened.returncode}")
        write_message({"ok": False, "error": "open_failed"})
        return
    write_diagnostic("add", "success")
    write_message({"ok": True})


if __name__ == "__main__":
    main()
