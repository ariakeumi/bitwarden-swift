- [x] Verify failing UI regressions for startup arrow navigation and multiline note editing.
- [x] Restore initial list focus.
- [x] Persist window frame, column widths and visibility.
- [x] Add a spacious, resizable multiline secure note editor.
- [x] Run focused UI journeys and relevant regression checks; build Release.

Validation (2026-10-24): 3 `VaultUsabilityJourneyTests` UI journeys and 17 related unit tests passed, including native window autosave/restoration and multiline draft round-tripping. Release built successfully with a temporary local bundle identifier override. UI tests used an isolated bundle identifier and local ad-hoc signing; no production signing configuration was changed.
