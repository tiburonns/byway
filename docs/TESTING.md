# Byway physical acceptance plan

This checklist validates the parts of Byway that cannot be proven by portable core tests alone. Run it before calling a build release-ready.

## Environment

- Two Apple devices signed into the same iCloud account, with iCloud Drive enabled.
- A development-signed Byway build using `byway.entitlements`.
- A second build or device available for offline/reconnect testing.
- Keep a copy of an encrypted v1 fixture and a current v2 encrypted backup.

## 1. iCloud propagation

1. On device A, create `QA.Sync.Text` with a unique value.
2. Confirm it appears on device B.
3. Change it on B and confirm A receives the new revision.
4. Repeat with Boolean, Integer, Array, Dictionary, Date, Location, and File values.
5. Move variables into a folder on A and confirm folder membership propagates to B.

Pass: values, metadata, folders, revisions, and file attachments converge without duplicate variables or silent data loss.

## 2. Concurrent edit conflict

1. Put both devices offline.
2. Edit the same variable on both devices with different values.
3. Make one edit have the higher revision.
4. Reconnect both devices.
5. Repeat with equal revision but different `updatedAt` values.
6. Repeat with equal revision and equal timestamp using controlled test data.

Pass: both devices converge on the deterministic precedence used by `VariableConflictResolver`: revision, then `updatedAt`, then UUID. No unresolved conflict remains indefinitely.

## 3. Corruption recovery

1. In a development test build, place an invalid JSON file in the active Variables directory.
2. Refresh Byway.
3. Confirm valid variables still load.
4. Confirm the damaged source is removed from the active directory only after its original bytes are preserved in `Quarantine`.
5. Open Settings and confirm the recovered-damaged-file count increases.
6. Repeat with a corrupted folder record.

Pass: healthy data remains usable and the damaged bytes are preserved rather than silently discarded.

## 4. Encrypted backup compatibility

1. Import a known v1 encrypted Byway archive with the correct passphrase.
2. Confirm preview counts before import.
3. Import it and verify values and attachments.
4. Repeat with an incorrect passphrase and confirm no data changes.
5. Export a new encrypted backup.
6. Confirm it is v2 using PBKDF2-HMAC-SHA256 + ChaCha20-Poly1305.
7. Import the new backup on the second device.

Pass: v1 remains readable; new archives are v2; wrong credentials never partially import data.

## 5. Import rollback

1. Export the current state.
2. Modify several variables.
3. Import the exported archive using Overwrite.
4. Use Undo Last Import.
5. Verify values, folders, attachments, and history return to the pre-import state.

Pass: the recovery point restores the prior state without orphaned attachments.

## 6. Offline and reconnect behavior

1. Disable network access.
2. Create and modify local variables.
3. Relaunch Byway while offline.
4. Restore network access.
5. Confirm iCloud eventually converges without UI lockups or duplicate records.

Pass: local use remains functional offline and sync recovery is non-destructive.

## Release gate

A release may be called physically validated only when all applicable sections above pass on real devices. CI success alone does not satisfy this gate.
