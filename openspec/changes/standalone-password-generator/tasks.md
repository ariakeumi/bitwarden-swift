- [x] Add unit and UI regressions before implementation; verify the unit regressions fail.
- [x] Add the generator window, ⌘G command, shared actions, and Chinese labels.
- [x] Verify secret lifetime with unit tests and the editor compatibility journey.
- [x] Build Release; keep UI checks to the basic journeys without additional password-length sweeps, as requested.

Validation: 33 related unit tests passed. The editor/standalone compatibility UI journey passed in an earlier run. Full UI runs encountered desktop window interference and a cancelled macOS automation authentication prompt; they were not repeated further following the user's request. Added native selectable-text identity refresh after observing stale preview accessibility values. Release compilation is checked separately from GUI automation.
