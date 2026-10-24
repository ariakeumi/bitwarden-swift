# Design

- Focus the native SwiftUI item list when its populated content first appears. Retain native list keyboard navigation and search/editor focus.
- Persist column visibility with `AppStorage` and measured widths in UI-only `UserDefaults` keys, ignoring collapsed and provisional startup measurements. Keep a separate width for verification codes, which require a wider minimum. Width writes do not invalidate the SwiftUI layout while the user drags a divider.
- Give the main window group a stable identifier. Apply saved native split-divider positions after the initial layout; SwiftUI's ideal widths otherwise reopen at the minimum widths on the tested macOS SDK.
- Restore and autosave the main window frame through AppKit at the app layer, across login/unlock/vault screen transitions.
- Replace the secure note single-line field with a native `TextEditor`, preserving optional empty-string handling and all newlines. Let the editor grow with the sheet while keeping custom fields accessible below it.
- Exercise startup arrow navigation, note paragraphs/discard, and saved column restoration through the existing in-memory UI-test vault. Test native window frame autosave/restoration with temporary `NSWindow` instances and unique autosave names.

## Complexity tracking

| Exception | Reason | Simpler alternative |
| --- | --- | --- |
| AppKit window frame autosave bridge in App | SwiftUI has no explicit API for restoring and autosaving a named window frame across the root screen transitions. Native AppKit autosave handles screen bounds and stores only geometry. | `defaultSize` supplies an initial size but does not explicitly restore the last frame. |
| AppKit split-divider restoration in App | The tested SwiftUI implementation reopens at minimum widths even when the saved ideal widths are supplied. Apply divider positions once after startup and when the column mode/visibility changes. | Supplying saved `navigationSplitViewColumnWidth` ideals alone failed the UI restoration regression. |
