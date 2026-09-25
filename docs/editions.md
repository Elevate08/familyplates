# Editions: the appliance and the hosted service

FamilyPlates comes in two editions, built from one codebase the way [Fizzy](https://github.com/basecamp/fizzy) is.

| | **Appliance** | **Hosted service** |
| :--- | :--- | :--- |
| Who runs it | Anyone, on their own hardware | David Spencer, one deployment |
| Households | One kitchen | Many, each isolated from the others |
| Sign-in | Profiles and PINs, optional passwords, passkeys, and optionally Google, Apple, OIDC or a forward-auth proxy | Email sign-in codes, passkeys, Google and Apple |
| Cost | Free, always entitled | 14-day trial, then a Stripe subscription |
| Image | `ghcr.io/elevate08/familyplates` (published on every release) | Built at deploy time, never published |
| Gemfile | `Gemfile` | `Gemfile.saas` (the core `Gemfile` plus the engine) |

Everything a family uses day to day is in both: recipes, the meal planner, the grocery list, the pantry, Cook Mode, calendar feeds, printing, data export, passkeys and device pairing.

## What only the hosted service has

These live in the `saas/` Rails engine, and an appliance doesn't contain them at all:

- **Billing:** Stripe subscriptions through Pay, the billing portal, trials, promotion codes, and the Stripe webhook handlers.
- **The operator console** at `/platform_admin`: operator accounts, the household health view, suspension, support replies, bulk operations, promotions, deletion requests, the billing actions, and the audit log.
- **Public sign-up**, for new households.
- **Customer support conversations** with the operator.
- **Deletion requests**, which ask the operator to delete a household.

An appliance has no operator, so there's no one to answer support or process a deletion request. The owner of the server has the data export and the server itself.

## How the edition is chosen

`FAMILYPLATES_MODE` picks the edition, before Rails loads:

- **Unset or `appliance`:** `config/boot.rb` loads the core `Gemfile`. There's no Pay or Stripe, and no hosted routes.
- **`hosted`:** `config/boot.rb` loads `Gemfile.saas`, which adds the `saas/` engine. The engine adds its routes, models and checks to the app.

Hosted mode without the engine refuses to boot with `HostedEditionMissingError`. That covers the appliance image, or `BUNDLE_GEMFILE` forced to `Gemfile`. `FamilyPlates.saas?` tells the code which edition it's running.

The Docker image follows the same rule: `docker build --build-arg EDITION=hosted` builds the hosted image, and the default builds the appliance. An appliance image deletes `saas/` after copying the app, so the hosted code isn't even on disk.

In development, `touch tmp/hosted.txt` switches `bin/rails` to the hosted edition, and deleting the file switches it back.

## How the core and the engine meet

The engine is a non-isolated Rails engine (`FamilyPlatesSaas::Engine`), so the moved classes and route helpers keep their names. It draws its routes into the app's own route set. The core exposes a few seams, which the engine fills in:

- `Authentication` declares empty `handle_suspended_household` and `ensure_household_entitled!` callbacks. The engine's `HostedAccess` concern overrides them, so they keep their place in the before-action chain.
- `hosted_render "name"` renders `saas/app/views/hosted/_name.html.erb` in the hosted edition, and nothing on an appliance. The admin dashboard's billing card, the profile menu's support link and the data page's deletion request all come in this way.
- `Household` and `User` gain their hosted associations and behaviour (`Household::Billing`, `Household::Operations`, `Household::Support`, `User::Support`) when the engine loads.

**The database schema is shared.** The hosted tables, such as the Pay tables and the operator tables, are in `db/schema.rb` and sit empty on an appliance. So both editions have one migration path, and an appliance database never has to be converted.

## Testing both editions

`bin/rails test` runs the appliance suite. `FAMILYPLATES_MODE=hosted bin/rails test` runs the hosted edition's suite, which is the core tests plus `saas/test`. Every test starts as an appliance and opts into hosted mode itself.

CI runs both suites, builds both images, and checks that the appliance image has no hosted code. The authorization matrix runs on both bundles. On the appliance bundle, its "every route has a row" check proves no hosted route exists. Playwright runs against the hosted edition, whose crawl reaches every route.

## License

Both editions are under the [O'Saasy License](../LICENSE.md). You may use, modify and self-host FamilyPlates freely, but you may not offer it to others as a competing hosted service.
