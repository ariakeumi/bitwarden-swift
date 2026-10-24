# Vault list multiple selection

- Regular vault and Archive lists support native macOS Command-click, Shift-click, and Command-A selection using stable item IDs.
- A single selection shows the item detail. Multiple selection shows its count and disables single-item edit/copy commands.
- Context menus apply Archive/Unarchive and Move to Trash to the contextual selection, with one confirmation for the full batch. Right-clicking an unselected row targets that row.
- Filtering and sync preserve IDs that remain visible; hidden or removed items are deselected. Sidebar changes, lock, and sign-out clear selection.
- Batch failures remain visible and do not deselect failed items merely because other items succeeded.
- Trash and verification-code lists retain their current single-selection interactions.

## Validation

Unit tests cover selection/detail synchronization, refresh and filtering, session cleanup, and batch success/failure. UI tests exercise Command-click, Shift-click, Command-A, returning to single selection, and batch confirmation cancellation.
