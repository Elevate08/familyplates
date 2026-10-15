# FamilyPlates v1.3.1 — fixes the upgrade from v1.2.0

**Upgrade now if v1.3.0 is crash-looping on an existing install.** v1.3.0 boots
fine on a fresh volume, but on a volume holding a v1.2.0 database the
container exits on every start with:

```
uninitialized constant CreatePayTables::Pay
/rails/db/migrate/20260904011438_create_pay_tables.pay.rb:11
```

The hosted billing migrations named the `pay` gem, which the appliance image
doesn't bundle. A fresh install loads `db/schema.rb` and never runs them, so
only upgrades hit it.

## Before you upgrade

### Your database is part-way through the upgrade

The migrations that ran before the failing one were saved, including the
household and family-member UUID conversion. The billing migration that failed
was rolled back, and nothing after it ran. **v1.3.1 carries on from exactly
that point**, so just start it on the same volume. There's nothing to undo first.

You should still have the backup you took before upgrading to v1.3.0. Keep it
until v1.3.1 is up and your data looks right.

### Rolling back to v1.2.0 instead

v1.2.0 can't read a database that has been part-way migrated. To go back, stop
the app, put your pre-v1.3.0 copy of `production*.sqlite3` back in the storage
volume (removing any `-wal`/`-shm` files left beside it), and start
`ghcr.io/elevate08/familyplates:1.2.0`.

## Fixed

- **Upgrading from v1.2.0 no longer crash-loops.** The three `pay` migrations
  use plain column types and SQL instead of the gem. Hosted databases end up
  with exactly the same tables and columns as before.

## Verification

CI now upgrades a v1.2.0 database, with data in it, to the current schema under
both editions' bundles. It fails unless the result is exactly `db/schema.rb`
and every household, member, recipe and plan survived the move. The fix was
also checked in Docker: a v1.2.0 volume, and the half-migrated volume v1.3.0
leaves behind, both boot on v1.3.1.

The full changelog is in [CHANGELOG.md](https://github.com/Elevate08/familyplates/blob/master/CHANGELOG.md#v131---2026-10-11).
