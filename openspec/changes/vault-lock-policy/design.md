# Design

Represent the policy in the Domain auth contract. Store the preference in
UserDefaults and retain a per-account vault key only in the existing device-local,
when-unlocked Keychain service for Never / On restart. Never store the master
password. On restart binds the retained session to kern.bootsessionuuid; failure
to obtain a boot identifier disables restoration. Require a matching random
session identifier in preferences, revoked before key deletion, so a failed
Keychain deletion cannot restore a manually locked session.

Restore keys and API state before performing the normal vault sync at launch.
Default and missing/corrupt/expired sessions fall back to the existing unlock flow.
Policy changes while locked take effect after the next successful unlock. Any
persistence failure is surfaced when changing settings and falls back to requiring
unlock on future launches. All successful auth paths update retained sessions.
