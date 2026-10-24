# Implementation

1. Add UI regressions for ⌘G, single-window reuse, copy/regenerate, reopen, menu access, and editor compatibility. Add unit regressions for preview and clipboard lifetime.
2. Add an opt-in, non-restoring SwiftUI Window scene and File command. Inject the existing randomness provider at the App layer.
3. Share generator controls between the standalone window and editor popover, with context-appropriate actions. Clear transient output on dismissal and timeout.
4. Preserve copied values independently of preview/model lifetime using a change-count-guarded cleanup task and the existing concealed clipboard marker.
5. Run focused unit/UI tests, inspect the UI, and build Release without changing production signing configuration.

No new dependencies or cryptographic algorithms. AppKit pasteboard access reuses the existing native clipboard path because SwiftUI has no equivalent clipboard API.

UI validation found the existing seeded fixture still accessed the login keychain at app initialization, blocking on developer credential permissions. Use a DEBUG-only in-memory keychain for `--ui-test-vault` so fixture journeys are independent of real credentials; Release keeps the existing keychain implementation.
