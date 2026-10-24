# Implementation plan

1. Verify UI regression tests fail against the current single-selection list; add selection and batch-operation unit tests.
2. Track selected IDs in VaultBrowserViewModel while preserving its existing single-item detail API. Reconcile selection after refreshed data arrives.
3. Bind the native List to selected IDs, use selection-aware context menus, and show a multiple-selection summary in the detail pane.
4. Reuse existing archive/delete use cases for batch operations; keep confirmation snapshots and error reporting.
5. Run focused tests, the complete unit suite, relevant UI journeys, and a Release build.

No new dependencies, server endpoints, vault persistence, or crypto changes are required.
