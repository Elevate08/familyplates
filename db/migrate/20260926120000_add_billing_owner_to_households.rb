class AddBillingOwnerToHouseholds < ActiveRecord::Migration[8.1]
  # The one user who may subscribe, cancel or open the Stripe portal for a
  # hosted household. A user, not a profile: admin profiles can be selected
  # from a shared screen, and that must not carry billing authority.
  #
  # No backfill. No existing column records who created or pays for a
  # household, and the first admin or the household email is a guess, not
  # evidence. Existing households stay nil until an operator assigns an owner
  # from explicit evidence (PlatformAdmin::BillingOwnerBackfill) or after
  # verifying who asks (PlatformAdmin::BillingOwnerRecovery).
  #
  # Deleting the user leaves the household with no billing owner rather than
  # blocking the deletion; recovery then assigns a new one.
  def change
    add_reference :households, :billing_owner_user, type: :string,
      foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
