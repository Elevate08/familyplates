class AddCheckoutAndAcknowledgmentTrackingToBillingConsents < ActiveRecord::Migration[8.1]
  # Each consent now also records where its Checkout attempt stands and where
  # its acknowledgment email stands, so neither depends on a request or a job
  # surviving:
  #
  # - checkout_state: "reserved" while Stripe is being asked for a session,
  #   "open" once Stripe returned one, "unknown" when Stripe's answer was lost,
  #   "expired" once the session can no longer complete, and "confirmed" once
  #   the subscription it started is active. A household holds at most one
  #   reserved, open or unknown attempt, enforced by the unique index below.
  # - paid_* and next_renewal_at: what Stripe reports was actually charged,
  #   for which period, and when it renews, as sent in the acknowledgment.
  # - acknowledgment_*: the email's attempts, when it is next due, its last
  #   error, and whether a send ended without knowing if it was delivered.
  def change
    add_column :billing_consents, :checkout_state, :string, null: false, default: "reserved"
    add_column :billing_consents, :checkout_error, :string
    add_column :billing_consents, :provider_invoice_id, :string
    add_column :billing_consents, :paid_amount_minor_units, :integer
    add_column :billing_consents, :paid_currency, :string
    add_column :billing_consents, :paid_at, :datetime
    add_column :billing_consents, :paid_period_start, :datetime
    add_column :billing_consents, :paid_period_end, :datetime
    add_column :billing_consents, :next_renewal_at, :datetime
    add_column :billing_consents, :acknowledgment_attempts, :integer, null: false, default: 0
    add_column :billing_consents, :acknowledgment_next_attempt_at, :datetime
    add_column :billing_consents, :acknowledgment_last_error, :string
    add_column :billing_consents, :acknowledgment_uncertain_at, :datetime
    add_column :billing_consents, :acknowledgment_failed_at, :datetime

    reversible { |direction| direction.up { backfill } }

    add_index :billing_consents, :household_id, unique: true,
      where: "checkout_state IN ('reserved', 'open', 'unknown') AND confirmed_at IS NULL",
      name: "index_billing_consents_on_household_id_open_checkout"
    add_index :billing_consents, :acknowledgment_next_attempt_at
  end

  private

  # Rows written before this migration: a session id means Stripe returned
  # one; none means the request ended before it was recorded, which is not
  # known to have failed. A claimed acknowledgment never marked sent may have
  # gone out, so it is not sent again without an operator.
  def backfill
    execute "UPDATE billing_consents SET checkout_state = 'confirmed' WHERE confirmed_at IS NOT NULL"
    execute "UPDATE billing_consents SET checkout_state = 'open' WHERE confirmed_at IS NULL AND checkout_session_id IS NOT NULL"
    execute "UPDATE billing_consents SET checkout_state = 'unknown' WHERE confirmed_at IS NULL AND checkout_session_id IS NULL"
    # Only the newest attempt per household keeps the reservation.
    execute <<~SQL
      UPDATE billing_consents SET checkout_state = 'expired'
      WHERE confirmed_at IS NULL AND checkout_state IN ('open', 'unknown')
        AND EXISTS (
          SELECT 1 FROM billing_consents newer
          WHERE newer.household_id = billing_consents.household_id
            AND newer.confirmed_at IS NULL AND newer.checkout_state IN ('open', 'unknown')
            AND (newer.accepted_at > billing_consents.accepted_at
              OR (newer.accepted_at = billing_consents.accepted_at AND newer.id > billing_consents.id))
        )
    SQL
    execute <<~SQL
      UPDATE billing_consents SET acknowledgment_next_attempt_at = confirmed_at
      WHERE confirmed_at IS NOT NULL AND acknowledgment_sent_at IS NULL AND acknowledgment_claimed_at IS NULL
    SQL
    execute <<~SQL
      UPDATE billing_consents SET acknowledgment_uncertain_at = acknowledgment_claimed_at,
        acknowledgment_last_error = 'Claimed before this migration and never marked sent'
      WHERE acknowledgment_sent_at IS NULL AND acknowledgment_claimed_at IS NOT NULL
    SQL
  end
end
