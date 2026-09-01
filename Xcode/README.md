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
- Count, find, update, delete, sort, and deduplicate list items
- Get, test, set, or remove dictionary entries with nested paths such as `Auto.Portrait`
- Append structured JSON values or UUID-backed events to `HISTORY.Events`
- Query events by category, action, date range, limit, and order, or get the latest matching event
- Retrieve location and measurement fields as structured Shortcut properties
- Read variable metadata and distinguish a missing variable from an explicit null
- Initialize a variable only when it does not exist
- Generate UUIDs
- Batch-set variables or run a rollback-protected multi-variable transaction
- Remove expired variables
- Import and export all or selected variables in a registered portable `.byway` archive, including stored files
- Create, list, and delete folders, move multiple variables between folders, and delete selected variables in one operation

All existing typed actions remain available. Every action can run without opening byway.

## Structured JSON for advanced actions

Plain JSON values are inferred automatically. Use a `$type` envelope when JSON cannot preserve the intended native type:

```json
{
  "SYS.Mode": "Auto",
  "SYS.ModeChangedAt": {
    "$type": "date",
    "value": "2026-08-31T18:00:00Z"
  },
  "NAV.Destination": {
    "$type": "location",
    "latitude": 25.6866,
    "longitude": -100.3161,
    "name": "Monterrey"
  },
  "HOME.Temperature": {
    "$type": "measurement",
    "value": 24.6,
    "unit": "°C"
  }
}
```

Pass that object to **Batch Set Variables** to commit every value together. Supported `$type` values are `text`, `boolean`, `integer`, `number`, `duration`, `measurement`, `date`, `location`, `url`, `data`, `array`, `dictionary`, and `null`.

**Run Variable Transaction** accepts an array of `set`, `ensure`, `delete`, `append`, `setDictionary`, and `removeDictionary` operations:

```json
[
  {"operation":"set","key":"SYS.Mode","value":"Auto"},
  {"operation":"ensure","key":"HISTORY.Events","value":[]},
  {
    "operation":"append",
    "key":"HISTORY.Events",
    "value":{
      "id":"A GENERATED UUID",
      "category":"Navigation",
      "action":"Start",
      "timestamp":"2026-08-31T18:00:00Z",
      "details":{"destination":"Monterrey"}
    }
  }
]
```

If validation or a write fails, the transaction restores every affected variable. A small on-disk journal also restores interrupted transactions on the next repository access.

## Events and results in Shortcuts

**Append Event** creates the UUID automatically when one is not supplied and initializes `HISTORY.Events` as an empty list when necessary. Event results expose `UUID`, `Category`, `Action`, `Date`, `Details JSON`, and `Event JSON` as separate Shortcut properties.

The structured result actions expose fields directly:

- **Get Dictionary Entry**: `Exists`, `Is Null`, `Type`, `JSON`, and `Text`
- **Get Location Details**: `Latitude`, `Longitude`, `Name`, `Altitude`, `Horizontal Accuracy`, and `Maps URL`
- **Get Measurement Details**: `Value`, `Unit`, and `Formatted Value`
- **Get Variable Metadata**: existence/null state, type, timestamps, expiration, tags, and revision
- **Find List Items**: zero-based index, type, JSON, text, and null state for every match

## Sharing variable setups

Use **Export Variables** in Shortcuts or **Settings → Export all variables** in the app. The generated `.byway` document is registered with iOS and contains values, metadata, folders, and stored file attachments. Another user can pass it to **Import Variables** and choose to keep existing keys, overwrite matching keys, or replace everything. Import validates the full archive before changing the store and commits its variables as one transaction.

## App features

- Search by key, tag, or notes
- Favorites
- Persistent folders, including empty folders
- Multi-selection with batch move and confirmed batch deletion
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
