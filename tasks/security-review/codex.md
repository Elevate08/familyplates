# Authentication and session security review (codex)

## Threat model

Entry points reviewed: appliance password and profile/PIN sign-in, hosted email codes, passkeys, external and forward auth, account/profile switching, transfer links, device pairing and session redemption, preferences, and household/operator administration. A guest can reach the public sign-in, passkey challenge, pairing, and transfer-link endpoints; a member can switch profiles and use household pages; an organizer can manage profiles and household settings; a kiosk carries a user session but is barred from account management and admin tools; an operator uses a separate session. The signed profile cookie, account session cookie, OAuth state, transfer link, pairing codes, and external provider responses cross distinct trust boundaries. Hosted requests must keep household membership and operator authority separate from the appliance's single-household defaults.

I checked authorization and tenant isolation; mass assignment; injection and XSS at these inputs and views; CSRF on state-changing routes; SSRF and redirects through provider configuration and callback URLs; secret exposure in logs, mail, and cookies; login/PIN/pairing rate limits; timing and enumeration signals; and insecure mode defaults. The findings below are limited to attacks I could reproduce or concerns that remain unproven.

## Findings

| Severity | File | Attack | Status | Commit |
| --- | --- | --- | --- | --- |
| High | `app/controllers/concerns/authentication.rb` | After appliance login is required, a previously issued signed profile cookie alone still grants organizer access without an account session. A controller test returned 200 for an unsigned-in organizer page on the old code. | fixed | `62c4b8c` |
| High | `app/models/family_member.rb`, `app/controllers/transfers_controller.rb` | A claimed four-hour transfer link can be replayed by a second signed-in account to overwrite the new profile owner. The old code changed the owner in the regression test. Links now bind to the owner at issuance and ownership is rechecked under a row lock. | fixed | `52405fd` |
| High | `app/controllers/concerns/authentication.rb` | Signing into a different appliance account with no linked profile leaves the previous organizer profile cookie active. The second account reached the organizer page on the old code without that profile's PIN. | fixed | `ba9030e` |
| Low | `app/controllers/passkeys_controller.rb` | `authentication_options` returns a user's credential IDs for a supplied email, which may allow passkey enrollment enumeration. I did not establish whether those IDs are usable or sensitive in this deployment or a compatible non-discoverable credential flow that avoids the disclosure. | suspected, not proven | — |
| Low | `app/controllers/device_pairings_controller.rb` | Anonymous pairing initiation has no explicit request rate limit and writes `DeviceGrant` rows. I did not establish a practical exhaustion rate or whether infrastructure rate limiting covers this endpoint. | suspected, not proven | — |

## Outside my scope

No reproducible issue outside the assigned files was established. No shared-file change was needed for the fixes above.

## Checked and found sound

- Hosted profile cookie resolution checks the signed-in user's household membership before setting `Current.household`; unauthenticated hosted requests discard profile cookies. Appliance account-required access now also requires an account session.
- The family member switch and profile selection paths resolve members from the current household or the signed-in user's own profiles; organizer switches verify a PIN and share an IP/profile throttle budget.
- Session tokens are looked up through `Session.find_by_token`, and revoked or expired sessions clear the account and profile cookies. Kiosk sessions are rejected by admin, passkey-management, device-management, and pairing-approval checks.
- Device codes are random; redemption is single use and polling enforces an interval. User codes are normalized before lookup. Session and profile cookies are signed, HTTP-only, and SameSite Lax.
- OAuth callbacks consume and compare session state and provider name. Forward auth is disabled by default and checks a configured trusted proxy address. Hosted email codes expire and are consumed; password, PIN, and operator sign-in endpoints have rate limits.
- Controller permitted attributes exclude role and account ownership on ordinary preference edits. Rails escaped templates and parameterized lookups did not reveal a reproducible SQL injection or XSS path in reviewed inputs. External redirects use configured provider or proxy URLs; I did not establish an attacker-controlled open redirect. No live keys or production services were used.

## Verification

Each regression test failed before its fix and passed afterward. The transfer test is tagged `@card-16.5`, and the account-required tests are tagged `@card-17.2`. On the final code tree: `bin/rails test` passed (1085 tests, 1 existing skip); `FAMILYPLATES_MODE=hosted bin/rails test` passed (1534 tests); both `bin/rails test:system` commands passed (52 tests each); `bin/rubocop` passed (341 files); `bin/brakeman --no-pager` passed (0 warnings); and `bin/coverage-criteria` passed (122/122). The sandboxed Brakeman wrapper initially crashed during its mandatory latest-release lookup; the required command passed with network access.
