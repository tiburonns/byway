#!/usr/bin/env python3
import json
import plistlib
import sys
import zipfile
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit("usage: validate_altstore_sources.py <ipa> <source.json> [source-es.json ...]")

ipa_path = Path(sys.argv[1])
source_paths = [Path(item) for item in sys.argv[2:]]

with zipfile.ZipFile(ipa_path) as archive:
    names = archive.namelist()
    info_path = next(
        name for name in names
        if name.startswith("Payload/") and name.endswith(".app/Info.plist")
    )
    info = plistlib.loads(archive.read(info_path))

    forbidden = [
        name for name in names
        if "_CodeSignature/" in name
        or name.endswith("embedded.mobileprovision")
        or name.startswith("__MACOSX/")
    ]
    if forbidden:
        raise SystemExit(f"IPA contains forbidden signing/metadata files: {forbidden[:5]}")

version = str(info["CFBundleShortVersionString"])
build = str(info["CFBundleVersion"])
bundle_id = str(info["CFBundleIdentifier"])
min_os = str(info.get("MinimumOSVersion", "17.0"))
expected_url = (
    "https://github.com/tiburonns/byway/releases/download/"
    f"v{version}/Byway-{version}.ipa"
)

if bundle_id != "com.tiburonns.byway":
    raise SystemExit(f"unexpected bundle identifier: {bundle_id}")

for source_path in source_paths:
    source = json.loads(source_path.read_text(encoding="utf-8"))
    app = source["apps"][0]

    if app.get("bundleIdentifier") != bundle_id:
        raise SystemExit(f"{source_path}: bundle identifier mismatch")

    versions = app.get("versions", [])
    if not versions:
        raise SystemExit(f"{source_path}: no versions")

    latest = versions[0]
    checks = {
        "version": version,
        "buildVersion": build,
        "downloadURL": expected_url,
        "minOSVersion": min_os,
    }
    for key, expected in checks.items():
        if str(latest.get(key)) != expected:
            raise SystemExit(
                f"{source_path}: latest {key}={latest.get(key)!r}, expected {expected!r}"
            )

    if int(latest.get("size", 0)) != ipa_path.stat().st_size:
        raise SystemExit(f"{source_path}: IPA size does not match source")

print(f"PASS: Byway {version} ({build}) IPA and {len(source_paths)} AltStore source(s) agree")
