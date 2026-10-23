# Changelog

## Unreleased

- Add a sort menu above the item list with saved name, modification date, and creation date ordering.

- Add Bitwarden-compatible Archive and Unarchive actions, an Archive sidebar with search,
  and archive-state preservation during edits, moves, attachment updates and delete/restore.
  Archived items are excluded from active lists, counts, global search and verification codes.

- Add ⌘R to sync the unlocked vault, with progress status and duplicate-request protection.
- Add ⌘1–⌘9 sidebar navigation and a Navigate menu listing the shortcuts.
- Rename the app and application bundle to `Bitvault`.

- Add Settings → Security → Lock Vault: Never, On restart (Mac restart), and
  On reopen (app restart, default). Retain sessions in device-local Keychain only
  when requested; manual lock and sign-out revoke restoration. These options replace
  automatic locking on sleep, screensaver and screen lock.
- Add Simplified Chinese (zh-Hans) localization: all UI strings, error messages, sidebar labels, and
  accessibility strings are localized through a String Catalog (`Prizm/Localizable.xcstrings`). User-
  facing error enums, display-name helpers, and detail-row labels now wrap their text in
  `String(localized:)`; view literals localize automatically. The shared scheme pins the unit-test
  language to English so text assertions stay locale-independent.
- Add verification codes: a login with a TOTP seed now shows its current one-time code and a
  countdown in the item, and a new "Codes" sidebar entry lists every item that has
  one. Supports base32 secrets and `otpauth://totp` links (SHA-1, SHA-256, SHA-512; 6 to 8 digits).
- **Changed**: "Copy Code" (⌃⌘C) now copies the current generated code instead of the raw TOTP
  seed, and the raw seed can no longer be copied.
- Fix a crash when locking the vault (including sleep and screen lock) by using
  the actual index ranges when zeroing sliced organization and vault key buffers.
