#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = (ROOT / "Xcode/byway.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
readme_en = (ROOT / "README.md").read_text(encoding="utf-8")
readme_es = (ROOT / "README.es.md").read_text(encoding="utf-8")

versions = set(re.findall(r"MARKETING_VERSION = ([0-9.]+);", project))
builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);", project))
if len(versions) != 1 or len(builds) != 1:
    raise SystemExit(f"version contract failed: versions={sorted(versions)} builds={sorted(builds)}")

version = next(iter(versions))
build = next(iter(builds))

if f"**Current `main`: {version} (build {build}).**" not in readme_en:
    raise SystemExit("version contract failed: English README is stale")
if f"**`main` actual: {version} (build {build}).**" not in readme_es:
    raise SystemExit("version contract failed: Spanish README is stale")

if "DEVELOPMENT_TEAM =" in project:
    raise SystemExit("build contract failed: repository must not hardcode an Apple Development Team")

if "CODE_SIGN_ENTITLEMENTS = byway/byway.local.entitlements;" not in project:
    raise SystemExit("build contract failed: local entitlement configuration is missing")
if "CODE_SIGN_ENTITLEMENTS = byway/byway.entitlements;" not in project:
    raise SystemExit("build contract failed: iCloud entitlement configuration is missing")

source_en = json.loads((ROOT / "AltStore/source.json").read_text(encoding="utf-8"))
source_es = json.loads((ROOT / "AltStore/source-es.json").read_text(encoding="utf-8"))

def published_signature(source):
    app = source["apps"][0]
    return [
        (
            item["version"],
            str(item["buildVersion"]),
            item["downloadURL"],
            int(item["size"]),
        )
        for item in app["versions"]
    ]

if published_signature(source_en) != published_signature(source_es):
    raise SystemExit("release contract failed: English and Spanish AltStore sources diverge")

def semver(value):
    return tuple(int(part) for part in value.split("."))

published = source_en["apps"][0]["versions"][0]["version"]
if semver(published) > semver(version):
    raise SystemExit(f"release contract failed: published {published} is newer than main {version}")

print(
    f"PASS: Byway main {version} (build {build}); "
    f"published AltStore {published}; local/iCloud build contract intact"
)
