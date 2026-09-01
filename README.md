# Byway

[Español](README.es.md) · English

Byway is a private data layer for Apple Shortcuts. It stores typed global variables, structured history, navigation, parking, music, and Home state so automations can share durable context without a Byway account or analytics service.

## Almost plug-and-play setup

1. Install Byway 0.4.0 from the [Byway AltStore source](https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source.json).
2. Open Byway once.
3. Download and open [Byway-Schema-3.byway](Distribution/Variables/Byway-Schema-3.byway), then choose **Overwrite matching keys**.
4. Import the 30 signed shortcuts from [Distribution/Shortcuts/en](Distribution/Shortcuts/en).
5. In Shortcuts, run **BYWAY — Initialize System** once and approve the requested Apple permissions.

The Spanish shortcut collection is available in [Distribution/Shortcuts/es](Distribution/Shortcuts/es).

## Language

Open **Byway → Settings → Language** and choose System Default, English, or Spanish. The choice is saved locally and applies immediately.

## AltStore

- English source: `https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source.json`
- Spanish source: `https://raw.githubusercontent.com/tiburonns/byway/main/AltStore/source-es.json`
- Manual IPA: see the latest GitHub release.

The AltStore build uses on-device storage so it can be re-signed without the developer's private iCloud entitlement. Import/export and Shortcuts integration remain available.

## Requirements

- iOS or iPadOS 17 or later
- AltStore Classic or another compatible IPA installer for the published IPA
- Apple Shortcuts

## Build and tests

```sh
./Tests/run-core-tests.sh
./Tests/run-intent-tests.sh
./Tests/run-shortcut-audit.sh
xcodebuild -project Xcode/byway.xcodeproj -scheme byway -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See [Distribution/README.md](Distribution/README.md) for package details.
