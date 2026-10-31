#!/usr/bin/env python3
"""Check the installed/local release's size, architecture and bundle integrity."""
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "app.pullr.Pullr"
assert info["CFBundleShortVersionString"] and info["CFBundleVersion"]
sparkle = app / "Contents/Frameworks/Sparkle.framework/Versions/Current"
for helper in ("Autoupdate", "Updater.app/Contents/MacOS/Updater", "XPCServices/Downloader.xpc/Contents/MacOS/Downloader", "XPCServices/Installer.xpc/Contents/MacOS/Installer"):
    assert (sparkle / helper).is_file() and os.access(sparkle / helper, os.X_OK), f"Missing executable helper: {helper}"
size = 0
binaries = 0
for directory, _, files in os.walk(app):
    for name in files:
        path = Path(directory) / name
        if path.is_symlink():
            continue
        size += path.stat().st_size
        with path.open("rb") as binary:
            magic = binary.read(4)
        if magic not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            continue
        architectures = subprocess.check_output(["lipo", "-archs", str(path)], text=True).strip()
        assert architectures == platform.machine(), f"Unused architecture: {path}: {architectures}"
        binaries += 1
assert binaries >= 6, "App or Sparkle helpers are missing"
assert size < 6 * 1024 * 1024, f"Local release exceeds 6 MiB: {size} bytes"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"PASS: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), {binaries} native binaries, {size:,} bytes; signatures valid")
