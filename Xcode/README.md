# byway

`byway` turns values from Apple Shortcuts into global, persistent variables that can be reused by other shortcuts, personal automations, devices, and future runs.

The project is a native SwiftUI app for iPhone, iPad, and Mac. It has no third-party dependencies, no account system, no analytics, and no byway server. Variables are stored locally and move to the user's private iCloud Drive container when iCloud is available.

## Included variable types

- Text
- Boolean
- 64-bit integer
- Decimal number
- Duration
- Measurement with unit symbol
- Array, including nested JSON values
- Dictionary, including nested JSON values
- Date
- Location with latitude, longitude, altitude, accuracy, and name
- URL
- Raw binary data
- File with filename and content type
- Explicit null

Images, PDFs, audio, video, contacts, and other Shortcut content can be preserved with the **File** type. This retains their original bytes and content type without requiring access to Photos, Contacts, or another private database.

## Shortcuts actions

The app includes actions to:

- Set and retrieve each supported value type
- Retrieve any variable as plain text or JSON
- Test whether a key exists
- List and search keys or filter them by tag
- Delete or rename variables
- Atomically toggle a Boolean
- Atomically increment a number
- Append items to an array
- Set or remove a dictionary entry
- Remove expired variables
- Import and export a portable `.byway` archive, including stored files

## App features

- Search by key, tag, or notes
- Favorites
- Optional expiration dates
- Per-change history with restore
- Self-contained backup, import, export, and sharing
- Automatic migration from local storage when the private iCloud container becomes available
- Per-variable files to reduce cross-device sync conflicts
- Case-insensitive keys and atomic file writes

## Open and run

1. Open `byway.xcodeproj` in Xcode 16 or newer.
2. Select the **byway** target, open **Signing & Capabilities**, and choose your Apple Developer team.
3. Keep the bundle identifier `com.tiburonns.byway`, or replace it with one owned by your team.
4. Add/confirm the **iCloud** capability with **iCloud Documents** enabled.
5. Select the container `iCloud.com.tiburonns.byway`. If the bundle identifier changes, update the container in:
   - `byway/byway.entitlements`
   - `byway/Persistence/StorageLocation.swift`
6. Run the app once on each device. Then open Shortcuts and search for **byway**.

The app still works with local-only storage when iCloud is unavailable. A paid Apple Developer team and an iCloud container are required to test private cross-device synchronization on physical devices.

## Architecture

- `Domain`: typed, recursive variable model and history records
- `Persistence`: actor-isolated local/iCloud document storage and portable archives
- `Intents`: App Intents exposed to Shortcuts and Siri
- `UI`: SwiftUI variable browser, editor, history, and settings
- `Support`: observable UI store and FileDocument integration

## Current deployment targets

- iOS / iPadOS 17.0+
- macOS 14.0+
- Swift 5 language mode
