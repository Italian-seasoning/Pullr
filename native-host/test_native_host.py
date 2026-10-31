#!/usr/bin/env python3
import base64
from pathlib import Path
import tempfile
import io
import json
import struct
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

from pullr_native_host import (
    best_music_match,
    build_deep_link,
    find_apple_music,
    save_listening_event,
    save_website_event,
    write_diagnostic,
    main,
)


with tempfile.TemporaryDirectory() as directory:
    jpeg = base64.b64encode(b"\xff\xd8\xff\xd9").decode("ascii")
    link = build_deep_link(
        {
            "url": "https://cdn.example/master.m3u8",
            "captureKind": "hls",
            "thumbnailDataURL": f"data:image/jpeg;base64,{jpeg}",
        },
        thumbnail_directory=directory,
    )
    thumbnail_url = parse_qs(urlparse(link).query)["thumbnailURL"][0]
    thumbnail_path = Path(urlparse(thumbnail_url).path)
    assert thumbnail_path.exists()
    assert thumbnail_path.read_bytes() == b"\xff\xd8\xff\xd9"

    preset_link = build_deep_link({
        "url": "https://youtube.com/watch?v=abc",
        "presetID": "3A4B5C6D-7E8F-4091-A120-AAAAAAAAAAAA",
        "start": True,
    })
    preset_query = parse_qs(urlparse(preset_link).query)
    assert preset_query["presetID"] == ["3a4b5c6d-7e8f-4091-a120-aaaaaaaaaaaa"]
    assert preset_query["start"] == ["1"]

    event = save_listening_event({
        "title": "Song",
        "artist": "Artist",
        "url": "https://music.youtube.com/watch?v=abc",
        "videoID": "abc",
        "seconds": 30,
    }, directory=directory, now=1234)
    assert event["seconds"] == 30
    assert (Path(directory) / "listening-history.jsonl").exists()

    website_event = save_website_event({
        "url": "https://www.youtube.com/watch?v=abc",
        "title": "Video",
        "seconds": 30,
    }, directory=directory, now=1234)
    assert website_event["site"] == "youtube.com"
    assert website_event["isYouTube"] is True
    assert website_event["url"] == "https://www.youtube.com/watch?v=abc"
    assert (Path(directory) / "website-activity.jsonl").exists()
    private_event = save_website_event({
        "url": "https://example.com/private/path?episode=7&token=secret#player",
        "title": "Private page title",
        "seconds": 10,
    }, directory=directory, now=1234)
    assert private_event["site"] == "example.com"
    assert private_event["title"] == "example.com"
    assert private_event["url"] == "https://example.com/"
    queued = {"id":"12345678-1234-4234-8234-123456789abc", "url":"https://example.com/", "seconds":30, "recordedAt":1000}
    save_website_event(queued, directory=directory, now=1234)
    save_website_event(queued, directory=directory, now=1234)
    records = (Path(directory) / "website-activity.jsonl").read_text().splitlines()
    assert sum(queued["id"] in record for record in records) == 1
    assert __import__("json").loads(records[-1])["recordedAt"] == 1000

    # Exercise Chrome's framed stdio route without opening or depending on Pullr.
    message = json.dumps({"action":"trackWebsite", "url":"https://example.com/", "seconds":5}).encode()
    reply = io.BytesIO()
    with patch('sys.stdin', SimpleNamespace(buffer=io.BytesIO(struct.pack('<I', len(message)) + message))), \
         patch('sys.stdout', SimpleNamespace(buffer=reply)), \
         patch('pathlib.Path.home', return_value=Path(directory)), \
         patch('subprocess.run', side_effect=AssertionError('Tracking must not launch the app')):
        main()
    framed = reply.getvalue()
    assert struct.unpack('<I', framed[:4])[0] == len(framed[4:])
    assert json.loads(framed[4:]) == {"ok":True}
    assert (Path(directory) / 'Library/Application Support/Pullr/website-activity.jsonl').exists()

    assert write_diagnostic("findAppleMusic", "no_match", directory=directory, now=1234)
    diagnostic = (Path(directory) / "native-host.jsonl").read_text()
    record = __import__("json").loads(diagnostic)
    assert set(record) == {"timestamp", "action", "outcome"}
    assert record["action"] == "findAppleMusic"
    assert "title" not in diagnostic and "https://" not in diagnostic

match = best_music_match("Artist - The Song (Official Video)", "", [
    {"trackName": "Wrong Song", "artistName": "Someone", "trackViewUrl": "https://music.apple.com/wrong"},
    {"trackName": "The Song", "artistName": "Artist", "trackViewUrl": "https://music.apple.com/right"},
])
assert match["trackViewUrl"] == "https://music.apple.com/right"

punctuation_candidates = [
    {"trackName": "Song", "artistName": "Artist", "trackViewUrl": "https://music.apple.com/plain"},
    {"trackName": "Song!", "artistName": "Artist", "trackViewUrl": "https://music.apple.com/exclamation"},
]
assert best_music_match("Song!", "Artist", punctuation_candidates)["trackViewUrl"].endswith("/exclamation")
assert best_music_match("Song!", "Artist", punctuation_candidates[:1]) is None
assert best_music_match("ASTRAL! - SUPER SLOWED", "xxephyrr", [
    {"trackName": "ASTRAL - SUPER SLOWED", "artistName": "xxephyrr", "trackViewUrl": "https://music.apple.com/wrong"},
    {"trackName": "ASTRAL! - SLOWED", "artistName": "xxephyrr", "trackViewUrl": "https://music.apple.com/slowed"},
]) is None
assert best_music_match("ASTRAL! - SUPER SLOWED", "xxephyrr", [
    {"trackName": "ASTRAL! - SUPER SLOWED", "artistName": "xxephyrr", "trackViewUrl": "https://music.apple.com/right"},
])["trackViewUrl"].endswith("/right")
assert best_music_match("曲!", "歌手", [
    {"trackName": "曲!", "artistName": "別人", "trackViewUrl": "https://music.apple.com/wrong"},
]) is None
assert best_music_match("Song", "", [
    {"trackName": "Song", "artistName": "Artist One", "trackViewUrl": "https://music.apple.com/one"},
    {"trackName": "Song", "artistName": "Artist Two", "trackViewUrl": "https://music.apple.com/two"},
]) is None
assert best_music_match("Song", "Artist", [
    {"trackName": "Song", "artistName": "Artista", "trackViewUrl": "https://music.apple.com/one"},
    {"trackName": "Song", "artistName": "Artistb", "trackViewUrl": "https://music.apple.com/two"},
]) is None
assert best_music_match("Don’t Stop", "Artist", [
    {"trackName": "Don't Stop", "artistName": "Artist", "trackViewUrl": "https://music.apple.com/right"},
])["trackViewUrl"].endswith("/right")

search_terms = []


def fake_music_search(endpoint):
    term = parse_qs(urlparse(endpoint).query)["term"][0]
    search_terms.append(term)
    if term == "AMORA":
        return {"results": [
            {"trackName": "AMORA", "artistName": "QMIIR & ngy Hortenzo", "trackViewUrl": "https://music.apple.com/amora"},
        ]}
    return {"results": [
        {"trackName": "Leih Mir, Amor", "artistName": "Someone Else", "trackViewUrl": "https://music.apple.com/wrong"},
    ]}


match = find_apple_music({"title": "AMORA", "artist": "QMIR"}, fetcher=fake_music_search)
assert match["trackViewUrl"] == "https://music.apple.com/amora"
assert search_terms == ["QMIR AMORA", "AMORA"]

print("Native host checks passed.")
