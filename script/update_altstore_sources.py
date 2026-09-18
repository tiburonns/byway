#!/usr/bin/env python3
import json
import plistlib
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit("usage: update_altstore_sources.py <ipa> <source.json> [source-es.json ...]")

ipa_path = Path(sys.argv[1])
source_paths = [Path(item) for item in sys.argv[2:]]

with zipfile.ZipFile(ipa_path) as archive:
    info_path = next(
        name for name in archive.namelist()
        if name.startswith("Payload/") and name.endswith(".app/Info.plist")
    )
    info = plistlib.loads(archive.read(info_path))

version = str(info["CFBundleShortVersionString"])
build = str(info["CFBundleVersion"])
min_os = str(info.get("MinimumOSVersion", "17.0"))
bundle_id = str(info["CFBundleIdentifier"])
size = ipa_path.stat().st_size
date = datetime.now(timezone.utc).date().isoformat()
download_url = (
    "https://github.com/tiburonns/byway/releases/download/"
    f"v{version}/Byway-{version}.ipa"
)

if bundle_id != "com.tiburonns.byway":
    raise SystemExit(f"unexpected bundle identifier: {bundle_id}")

for source_path in source_paths:
    source = json.loads(source_path.read_text(encoding="utf-8"))
    app = source["apps"][0]
    if app["bundleIdentifier"] != bundle_id:
        raise SystemExit(f"{source_path}: bundle identifier mismatch")

    is_spanish = source_path.name.endswith("-es.json")
    versions = app.setdefault("versions", [])

    existing = next(
        (item for item in versions if item.get("version") == version),
        None,
    )
    description = (
        "Actualización de calidad y estabilidad de Byway. "
        "Consulta las notas de la release para ver los cambios de esta versión."
        if is_spanish else
        "Byway quality and stability update. "
        "See the release notes for the changes in this version."
    )

    new_entry = {
        "version": version,
        "buildVersion": build,
        "date": date,
        "localizedDescription": (
            existing.get("localizedDescription", description)
            if existing else description
        ),
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": min_os,
    }

    versions[:] = [item for item in versions if item.get("version") != version]
    versions.insert(0, new_entry)

    news = source.setdefault("news", [])
    identifier = f"byway-{version}-{'es' if is_spanish else 'en'}"
    if not any(item.get("identifier") == identifier for item in news):
        news.insert(0, {
            "title": (
                f"Byway {version} ya está disponible"
                if is_spanish else
                f"Byway {version} is available"
            ),
            "identifier": identifier,
            "caption": (
                "Actualización de calidad, estabilidad y compatibilidad."
                if is_spanish else
                "Quality, stability, and compatibility update."
            ),
            "date": date,
            "tintColor": "#0A84FF",
            "notify": True,
        })

    source_path.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

print(f"Updated {len(source_paths)} AltStore source(s) for Byway {version} ({build})")
