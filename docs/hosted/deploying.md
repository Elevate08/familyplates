# Deploying the hosted service

The hosted FamilyPlates service is deployed with [Kamal](https://kamal-deploy.org) to one server. Appliances don't use any of this: they run the published appliance image with Docker Compose (see [Getting started](../getting-started.md)).

Kamal builds the hosted image (`EDITION=hosted`) from the committed code at deploy time, pushes it to a registry on the server over SSH, and runs it behind kamal-proxy, which terminates TLS with a Let's Encrypt certificate. The image is never published anywhere.

## What you need

- A server running Linux, reachable over SSH as root (or set `HOSTED_SSH_USER`). `bin/kamal setup` installs Docker on it.
- A DNS `A` record pointing your hostname at the server, with ports 80 and 443 open.
- An SMTP provider. Hosted sign-in emails a code, and the app won't start without `SMTP_ADDRESS`.
- A Stripe account with the two recurring prices and a webhook endpoint. See [Stripe billing](stripe-billing.md).

## Settings and secrets

Nothing about the server is committed. `saas/config/deploy.yml` reads its settings from your environment, and `saas/.kamal/secrets` reads the secrets from it too. The simplest setup is a `.env.hosted` file at the repository root. It's gitignored (`.env.*`), and `deploy.yml` loads it:

```sh
# Where and what
HOSTED_SERVER=203.0.113.10          # the server's address
APP_HOST=plates.example.com         # the public hostname
SMTP_ADDRESS=smtp.example.com
SMTP_PORT=587
MAILER_DEFAULT_FROM="FamilyPlates <no-reply@plates.example.com>"
STRIPE_MONTHLY_PRICE_ID=price_...
STRIPE_ANNUAL_PRICE_ID=price_...

# Secrets
SECRET_KEY_BASE=...                 # bin/rails secret
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...          # bin/rails db:encryption:init
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...  # (same command)
SMTP_USERNAME=...
SMTP_PASSWORD=...
STRIPE_PRIVATE_KEY=sk_live_...
STRIPE_SIGNING_SECRET=whsec_...
```

To keep the secrets in a password manager instead, change `saas/.kamal/secrets` to use `kamal secrets fetch`. The file has an example.

**Keep `SECRET_KEY_BASE` and both encryption values safe, and never change them.** Losing the encryption keys makes encrypted columns unreadable, and changing `SECRET_KEY_BASE` signs everyone out.

## First deploy

```sh
bin/kamal setup
```

This installs Docker and kamal-proxy on the server, builds and pushes the image, and starts the app. The app prepares its SQLite databases on boot, in the `familyplates_hosted_storage` volume.

Then create the first operator account for the console at `/platform_admin`:

```sh
bin/kamal app exec -i "bin/rails platform_admin:create EMAIL=you@example.com PASSWORD='a-long-unique-password'"
```

It prints a TOTP provisioning URI. Add it to an authenticator before you sign in. See [Operator console](operator-console.md).

## Every deploy after that

```sh
bin/kamal deploy
```

Kamal deploys the commit you have checked out, so deploy from a release tag, for example `git switch --detach v1.3.0`. The new container has to pass its `/up` health check before kamal-proxy moves traffic to it. Migrations run on boot (`bin/rails db:prepare`), before the app takes requests.

Useful aliases: `bin/kamal console`, `bin/kamal logs`, `bin/kamal shell`, `bin/kamal dbc`.

## Rolling back

```sh
bin/kamal app containers   # lists the versions still on the server
bin/kamal rollback <version>
```

A rollback starts an older image, but it doesn't undo migrations. If the release you're leaving ran a migration the old code can't live with, restore the database from a backup taken before the deploy.

## Backups

Everything the service stores is in the `familyplates_hosted_storage` Docker volume: the SQLite databases (`storage/production*.sqlite3`) and uploaded recipe images. Back it up on a schedule, and before every deploy that migrates. For a consistent copy of a live database, use `sqlite3 storage/production.sqlite3 ".backup /path/to/copy.sqlite3"` rather than copying the file.

## Checking the deploy config

CI runs `bin/kamal config` with placeholder values on every change, so a broken `deploy.yml` fails the build before it fails a deploy. To see the resolved config yourself, run `bin/kamal config`. Note that its output includes your secrets.
