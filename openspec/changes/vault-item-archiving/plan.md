# Implementation plan

1. Add failing tests for optional archive metadata, encrypted edit round trips, archive filtering/search/counts and metadata retention.
2. Carry archivedDate through RawCipher, VaultItem and DraftVaultItem; add the archive selection and active/archive indexes.
3. Add the authenticated archive/unarchive API method, repository mutation and Domain use case with AppContainer injection. Use the server response and preserve the cache on failures.
4. Add the sidebar destination, confirmation, context/toolbar actions, detail banner, empty state and Simplified Chinese strings. Keep existing navigation shortcuts.
5. Validate the complete unit suite, attempt UI journeys and compile Release. Record local test-environment limitations.

Constitution check: native UI, inward protocol dependencies, no new crypto/dependencies/persistence, server-authoritative authorization, logged/surfaced errors and accessible action labels.
