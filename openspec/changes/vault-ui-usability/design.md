# Design

- Focus the native SwiftUI item list when its populated content first appears. Retain native list keyboard navigation and search/editor focus.
- Persist sidebar and item column widths and column visibility in `AppStorage`; ignore collapsed column measurements. Keep a separate width for verification codes, which require a wider minimum.
- Restore and autosave the main window frame through AppKit at the app layer, across login/unlock/vault screen transitions.
- Replace the secure note single-line field with a native `TextEditor`, preserving optional empty-string handling and all newlines. Let the editor grow with the sheet while keeping custom fields accessible below it.
- Exercise startup arrow navigation, note paragraphs/discard, and layout restoration through the existing in-memory UI-test vault.

## Complexity tracking

| Exception | Reason | Simpler alternative |
| --- | --- | --- |
| AppKit window frame autosave bridge in App | SwiftUI has no explicit API for restoring and autosaving a named window frame across the root screen transitions. Native AppKit autosave handles screen bounds and stores only geometry. | `defaultSize` supplies an initial size but does not explicitly restore the last frame. |
