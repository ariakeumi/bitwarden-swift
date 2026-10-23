- [x] Write and run failing archive metadata/filtering tests (missing fields/selection verified before implementation).
- [x] Implement metadata, indexes, endpoints and use case.
- [x] Wire sidebar, list, confirmation, toolbar, banner and localization.
- [x] Run unit tests, attempt UI verification and build Release; document limitations.

## Validation

- Complete unit suite: **581 passed, 0 failed**, run serially with `-parallel-testing-enabled NO`. An initial parallel run hit an existing shared-pasteboard test failure; serial execution passed.
- Release build: passed with the repository's unsigned local-build settings, using the isolated `build/archive-validation` derived-data directory.
- `git diff --check`: passed.
- Added UI journeys for archive visibility/search/detail, confirmation cancellation and archived-code exclusion, while retaining the existing navigation shortcut journey. UI execution could not complete in this environment: the app's bundle identifier is absent in the existing project configuration; a command-only temporary identifier got past that check, but the unsigned runner was killed before connecting. Manual local test signing did not establish a working runner connection. No passing UI result is claimed.
- No live vault credentials or production server writes were used. API contracts were verified against the Bitwarden and Vaultwarden source endpoints and tested using URLProtocol responses.

Logs/results: `build/test-archive-serial.log`, `build/build-archive-release.log`, and `build/archive-validation/Logs/Test/` (git-ignored local artifacts).
