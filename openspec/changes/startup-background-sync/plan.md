# Implementation plan

1. Add regression tests proving vault entry does not wait for synchronization and cancellation prevents vault publication.
2. Make UnlockViewModel report authentication success directly; retain biometric enrollment behavior.
3. Start post-unlock synchronization in RootViewModel using the existing cancellable manual-sync lifecycle and status UI. Preserve the next-run-loop layout boundary.
4. Add cancellation checkpoints to SyncRepositoryImpl, including before final publication.
5. Run focused authentication/sync tests, then the unit suite and Release build.

No new dependencies, persistence, crypto algorithms, or polling are needed. Initial login keeps its existing synchronization flow.

## Verification completed

- Verified regression failures before implementation, including blocking startup, premature sync timestamps, ignored cancellation, and retained UI snapshots.
- All 54 focused startup/unlock/sync tests passed.
- Full unit suite: 601 passed, 0 failed, 0 skipped.
- `./build.sh` Release build passed; output: `build/Build/Products/Release/Bitvault.app`.
- `git diff --check` passed.
