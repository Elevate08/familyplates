# Security review: grok

Scope: the hosted edition in `saas/` (billing, Stripe webhooks, operator console, sign-up, support, deletion, deploy secrets). Branch `security/grok`.

## Threat model

The hosted process is the same Rails app with `FAMILYPLATES_MODE=hosted`, which loads the `saas/` engine. Trust boundaries that matter here:

| Boundary | Who is on the outside | What they can reach |
| :--- | :--- | :--- |
| Public HTTP | Guest | Sign-up, sign-in, `/pay/webhooks/stripe` |
| Household session | Member, organizer, kiosk profile | Own household's billing page, support threads, deletion request |
| Another household | Organizer of a different kitchen | Must not read or change this kitchen, including by Checkout session id |
| Operator session | owner, billing, support, privacy | Every household. Money movement is supposed to be owner and billing only |
| Stripe | Webhook deliveries and API responses | Signature proves the bytes were signed. It does not by itself prove Stripe still agrees with a destructive payload, and Stripe delivers the same event more than once |

Assets: subscription entitlement, refunds and comps, promotion discounts, household PII (names, emails), support conversations, operator sessions, Stripe and SMTP secrets.

## Findings

| Severity | File | Attack | Status |
| :--- | :--- | :--- | :--- |
| High | `saas/app/services/platform_admin/bulk_operation_service.rb`, `saas/app/controllers/platform_admin/promotion_programs_controller.rb` | A support or privacy operator extends every household's trial (the days field was only capped in the browser, so 36500 was accepted) or creates and assigns a discount. Cancel, refund, and comp already reject those roles. | Fixed in `809d303` |
| High | `saas/config/initializers/stripe_webhook_authenticity.rb` | A second delivery of `invoice.payment_failed` emails the organizer again. Stripe retries for days with a new signature, and Pay kept no event id. | Fixed in `d1cad4d` |
| High | `saas/config/initializers/stripe_webhook_authenticity.rb` | A signed `customer.deleted` cancels the household's subscriptions from the payload alone, even when Stripe still has that customer. | Fixed in `d1cad4d` |
| Medium | `saas/app/controllers/subscriptions_controller.rb` | The subscription page syncs whatever `stripe_checkout_session_id` is in the query. An organizer who learned another household's Checkout session id could make the app retrieve and apply it. | Fixed in `eae0b01` |
| High | `saas/app/controllers/subscriptions_controller.rb` | In production, Subscribe with no Stripe secret created a fake active subscription and granted the kitchen. | Fixed in `4c1454a` |
| Medium | `saas/app/controllers/signups_controller.rb` | Signup sent a verification email on every request and accepted unlimited guesses of the code. A long household name was stored with no limit. | Fixed in `d23bf8d` |
| Medium | `saas/app/models/platform_admin_account.rb` | A captured authenticator code signed the operator in again after they signed out, for as long as the code was still in its ±30 second window. | Fixed in `3762f4e` |
| Low | `saas/lib/family_plates_saas/stripe_sandbox.rb` | Pay's default is to process `livemode: false` events when `STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS` is unset. | Hardened in `06d8419` |
| Low | `saas/app/services/platform_admin/household_billing.rb` | Two overlapping refund requests can both read the same remaining balance and both call Stripe before either updates `amount_refunded`. A second request after the first has finished is refused. | Suspected, not proven. Not changed. A row lock would close the window; a threaded test against the transactional test database does not demonstrate it reliably. |
| Low | `saas/app/models/platform_admin_account.rb` | `otp_secret` is stored in plaintext. A database copy is enough to mint authenticator codes. | Suspected. Encrypting the column needs a migration, which this review cannot add. |
| Low | `saas/app/controllers/platform_admin/deletion_requests_controller.rb` | Any operator role, including support, can permanently delete a household after typing its name. Billing changes are role-gated; deletion is not. | Suspected. The acceptance criteria say "the operator" can delete, so this may be intended. Not changed. |
| Low | `saas/app/views/platform_admin/sessions/new.html.erb` | The development sign-in page prints `OperatorPassword123!` and the current authenticator code when `operator@familyplates.local` exists. The account is not seeded, and the block is `Rails.env.development?` only. | Suspected. Not a production disclosure unless that account is created with that password and the app is booted in development. |
| Info | `saas/app/models/platform_audit_event.rb` | Audit search does not escape `%` and `_` in `LIKE`. An operator searching for `%` matches every row. They can already list the log. | Suspected, not a cross-tenant leak. Not changed. |
| Info | `saas/app/views/platform_admin/households/show.html.erb` | A charge `receipt_url` or `stripe_receipt_url` is rendered as an `href` with no scheme allowlist. Stripe sets that URL. A `javascript:` value in the column would run in the operator console. | Suspected. No path found that writes an attacker-controlled URL there. |

## Commits

| Commit | What an attacker could do, now closed |
| :--- | :--- |
| `809d303` | Support or privacy operator grants free time or a discount, including a trial measured in decades |
| `d1cad4d` | Replayed `invoice.payment_failed` emails again; signed `customer.deleted` ends access while Stripe still has the customer |
| `eae0b01` | Organizer syncs a Checkout session that belongs to another household |
| `4c1454a` | Production Subscribe with no Stripe key creates a free active subscription |
| `d23bf8d` | Signup floods an inbox, grinds the verification code, or stores an unbounded name |
| `3762f4e` | Captured authenticator code is accepted a second time inside its validity window |
| `06d8419` | Production processes Stripe test-mode events because the Pay default is on |

## What was checked and held

- **Webhook signature.** Pay returns 400 and stores nothing when `Stripe-Signature` is wrong. Covered by `saas/test/integration/stripe_webhook_states_test.rb`.
- **Entitlement mapping.** Signed subscription events still map active, trialing, past_due, incomplete, unpaid, paused, and deleted onto the household's access. The replay guard keys on Stripe's event id, not the subscription id, so a later update of the same subscription still applies.
- **Operator sign-in.** Unknown email, wrong password, and a deactivated account share one error and the same bcrypt cost. Ten failures from an address stop the next attempt. The session token is hashed. The cookie is `httponly`, `same_site: lax`, and `secure` on TLS.
- **Money movement on the household page.** Cancel, refund, and comp require an owner or billing operator and a reason. Comp is 1 to 12 months. A refund is limited to the remainder of that household's charge; another household's charge id is a 404. Amounts are parsed as dollars with `BigDecimal`, not a float.
- **Tenant isolation of support and deletion.** A customer only loads threads on `current_household`. Deletion requires an organizer, one open request, and the household name typed exactly.
- **Sign-up enumeration.** A new address and an address that already has a user get the same "we sent a code" response. The code is 6 characters from a 32-symbol alphabet, lives 15 minutes, and is deleted on success (now every open code for that address).
- **Hosted access checks.** Suspension and entitlement run in the authentication `before_action` chain. Rails halts the chain when a callback redirects.
- **Secrets in deploy config.** `saas/config/deploy.yml` and `saas/.kamal/secrets` reference environment variables. No key material is committed. The test-environment live-key boot guard was not weakened.
- **Test-only operator sign-in.** The route exists only when `Rails.env.test?`, and the controller returns 403 otherwise.
- **Household search.** The operator search escapes `%`, `_`, and `\` before the `LIKE`.

## Outside my scope

Nothing outside `saas/` was changed.

No proven vulnerability outside this scope was finished enough to write a reproduction. Pay's own `CustomerDeleted` handler is the code that trusted the payload; the guard lives in a hosted initializer because the gem is not in this tree to patch.

## Shared files

No route, gem, or migration was required. Encrypting `platform_admins.otp_secret` would need a migration under `db/migrate/`, which this review cannot add.
