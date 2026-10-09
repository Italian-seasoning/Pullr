"""Build portable runtime and source ZIPs with relative archive paths."""
from pathlib import Path
import hashlib
import json
import zipfile

base = Path(__file__).resolve().parent
source = base / "chrome-extension"
packages = base / "packages"
packages.mkdir(exist_ok=True)
version = json.loads((source / "manifest.json").read_text())["version"]

files = sorted(file for file in source.rglob("*") if file.is_file() and not file.name.startswith("."))
for name, runtime in [("PullrChrome.zip", True), ("PullrChrome-source.zip", False)]:
    destination = packages / name
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in files:
            relative = file.relative_to(source)
            if runtime and (relative.parts[0] == "tests" or file.name.startswith("test_") or (file.suffix == ".md" and file.name not in ["README.md", "PRIVACY.md"])):
                continue
            archive.write(file, relative.as_posix())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert json.loads(archive.read("manifest.json"))["version"] == version
        assert all(not name.startswith("/") and ".." not in Path(name).parts for name in archive.namelist())
    checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f"{name} {version} SHA-256 {checksum}")
