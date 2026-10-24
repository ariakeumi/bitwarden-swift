# Startup background sync

- A restored session or successful password/Touch ID unlock opens the vault browser without waiting for network sync or vault decryption.
- RootViewModel owns the post-unlock sync task, shares its in-flight state with manual sync, and refreshes items and the successful-sync timestamp only after completion.
- Sync errors remain visible in the vault browser and preserve the previous successful-sync timestamp.
- Manual sync cannot overlap startup sync. Lock and sign-out cancel and drain the task before clearing vault data and keys.
- Lock and sign-out clear decrypted UI snapshots and invalidate reads from the previous session so the next unlock cannot briefly display stale credentials.
- A cancelled sync must stop before publishing decrypted data. Existing authentication and lock-policy checks remain required.
- Vault data remains in memory only; after a fresh launch items appear when the background sync completes.

## Validation

Cover delayed startup sync, password/biometric unlock, successful and failed sync timestamps, duplicate sync prevention, cancellation on lock/sign-out, and repository cancellation.
