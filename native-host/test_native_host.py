#!/usr/bin/env python3
import base64
from pathlib import Path
import tempfile
import io
import json
import struct
import subprocess
import sys
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
    tracking_import_check = subprocess.run([sys.executable, "-c", """
import sys
class MusicOnlyImports:
    def find_spec(self, fullname, path=None, target=None):
        if fullname in {'difflib', 'subprocess', 'urllib.request'}:
            raise AssertionError('Website tracking loaded music or app-launch code: ' + fullname)
sys.meta_path.insert(0, MusicOnlyImports())
from pullr_native_host import save_website_event
assert save_website_event({'url':'https://example.com/', 'seconds':5}, directory=sys.argv[1])
""", directory], cwd=Path(__file__).parent, capture_output=True, text=True)
    assert tracking_import_check.returncode == 0, tracking_import_check.stderr
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

for artist in ["Earth, Wind & Fire", "Simon & Garfunkel", "Hall & Oates"]:
    assert best_music_match("September", artist, [
        {"trackName": "September", "artistName": artist, "trackViewUrl": "https://music.apple.com/right"},
    ])["trackViewUrl"].endswith("/right")

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
possible = best_music_match("Song", "The Beatles", [
    {"trackName": "Song", "artistName": "The Beatle", "trackViewUrl": "https://music.apple.com/possible"},
])
assert possible and possible["requiresConfirmation"] is True
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

def vevo_search(endpoint):
    term = parse_qs(urlparse(endpoint).query)["term"][0]
    if term == "Rick Astley Never Gonna Give You Up":
        return {"results": [{"trackName": "Never Gonna Give You Up", "artistName": "Rick Astley", "trackViewUrl": "https://music.apple.com/rick"}]}
    return {"results": []}

match = find_apple_music({"title": "Rick Astley - Never Gonna Give You Up", "artist": "RickAstleyVEVO"}, fetcher=vevo_search)
assert match and match["trackViewUrl"].endswith("/rick")

def exact_title_search(endpoint):
    return {"results": [
        {"trackName": "ASTRAL! - SUPER SLOWED", "artistName": "xxephyrr", "trackViewUrl": "https://music.apple.com/astral"},
        {"trackName": "SUPER SLOWED", "artistName": "ASTRAL!", "trackViewUrl": "https://music.apple.com/wrong"},
    ]}

match = find_apple_music({"title": "ASTRAL! - SUPER SLOWED", "artist": "xxephyrr"}, fetcher=exact_title_search)
assert match and match["trackViewUrl"].endswith("/astral")

def misleading_title_search(endpoint):
    return {"results": [{"trackName": "Extended", "artistName": "Name", "trackViewUrl": "https://music.apple.com/wrong"}]}

for channel in ["UnrelatedUploader", "Name Music"]:
    possible = find_apple_music({"title": "Name - Extended", "artist": channel}, fetcher=misleading_title_search)
    assert possible and possible["requiresConfirmation"] is True
possible = find_apple_music({"title": "Extended", "artist": ""}, fetcher=misleading_title_search)
assert possible and possible["requiresConfirmation"] is True

def run_music_action(message, match=None):
    data = json.dumps(message).encode()
    reply = io.BytesIO()
    with tempfile.TemporaryDirectory() as directory, \
         patch('sys.stdin', SimpleNamespace(buffer=io.BytesIO(struct.pack('<I', len(data)) + data))), \
         patch('sys.stdout', SimpleNamespace(buffer=reply)), \
         patch('pathlib.Path.home', return_value=Path(directory)), \
         patch('pullr_native_host.find_apple_music', return_value=match), \
         patch('subprocess.run', return_value=SimpleNamespace(returncode=0)) as opened:
        main()
    return json.loads(reply.getvalue()[4:]), opened

suggestion = {"trackName": "Extended", "artistName": "Name", "trackViewUrl": "https://music.apple.com/ca/album/example/1", "requiresConfirmation": True}
reply, opened = run_music_action({"action": "findAppleMusic", "title": "Song"}, {"trackName": "Song", "artistName": "Artist", "trackViewUrl": "https://music.apple.com.attacker.example/track"})
assert reply["ok"] is False
opened.assert_not_called()
reply, opened = run_music_action({"action": "findAppleMusic", "title": "Name - Extended"}, suggestion)
assert reply["error"] == "confirm_match" and reply["title"] == "Extended"
opened.assert_not_called()
reply, opened = run_music_action({"action": "openAppleMusicMatch", "url": suggestion["trackViewUrl"]})
assert reply["ok"] is True
opened.assert_called_once()
reply, opened = run_music_action({"action": "openAppleMusicMatch", "url": "https://music.apple.com.attacker.example/track"})
assert reply["ok"] is False
opened.assert_not_called()
for url in ["http://music.apple.com/track", "https://user@music.apple.com/track", "https://music.apple.com:444/track"]:
    reply, opened = run_music_action({"action": "openAppleMusicMatch", "url": url})
    assert reply["ok"] is False
    opened.assert_not_called()

print("Native host checks passed.")
