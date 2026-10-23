# Design

Use the server's optional `archivedDate` metadata end to end (RawCipher → VaultItem → DraftVaultItem → RawCipher). Preserve the exact timestamp string so edits cannot accidentally unarchive an item, including on Vaultwarden. Missing/null means active. New items start unarchived.

Archive/unarchive uses authenticated, bodyless `PUT /api/ciphers/{id}/archive` and `/unarchive`, decoding the returned cipher to obtain server-confirmed state. No plaintext or keys are sent. Validate the item exists and is not trashed. Rebuild indexes only after success, and re-find the item after awaits to avoid stale array indices. Refresh lists/counts and clear the affected selection. Errors are logged and shown through the existing action alert; unsupported servers and subscription restrictions remain server-authoritative.

Add a Domain use-case protocol, Data implementation and AppContainer injection. Reuse the regular list for Archive, with an archive-specific empty state, a context action, toolbar action and detail status banner. Require confirmation before archiving. Keep existing ⌘1–⌘9 bindings stable. Global search excludes archives; typing within Archive searches that scope.

Preserve archive metadata in every cache copy (attachments, delete/restore, moves and folder deletion). Tests cover wire compatibility, encryption round trips, filtering/counts/search, archive/unarchive success and errors, metadata retention, and UI archive visibility.

References:
- https://bitwarden.com/help/managing-items/#archive
- https://github.com/dani-garcia/vaultwarden/blob/main/src/api/core/ciphers.rs
- https://github.com/bitwarden/server/blob/main/src/Api/Vault/Controllers/CiphersController.cs

Constitution review: native SwiftUI, Domain-only contracts, unchanged vetted crypto, no new dependencies or secret persistence, accessible labels, test-first implementation. Existing DEVELOPMENT.md unsigned build workflow applies to local validation.
