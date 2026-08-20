#!/usr/bin/env python3
import base64
from pathlib import Path
import tempfile
from urllib.parse import parse_qs, urlparse

from pullr_native_host import (
    best_music_match,
    build_deep_link,
    find_apple_music,
    save_listening_event,
    write_diagnostic,
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
