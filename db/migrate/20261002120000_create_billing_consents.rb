class CreateBillingConsents < ActiveRecord::Migration[8.1]
  # Evidence that a household's billing owner agreed to a paid, automatically
  # renewing plan before Checkout: who, for which household, the disclosure
  # they saw word for word, and the price Checkout was asked to charge. It is
  # tied to the Checkout session and, once Stripe reports the subscription
  # active, to that subscription. No card data: Stripe collects the card.
  #
  # No foreign keys. The record is consent evidence that must outlive the
  # household and the user it names, so deleting either leaves it in place.
  def change
    create_table :billing_consents, id: :string do |t|
      t.string :user_id, null: false
      t.string :household_id, null: false
      t.string :terms_version, null: false
      t.text :disclosure, null: false
      t.string :disclosure_digest, null: false
      t.string :plan_key, null: false
      t.string :stripe_price_id
      t.string :currency, null: false
      t.integer :amount_minor_units, null: false
      t.string :interval, null: false
      t.datetime :accepted_at, null: false
      t.string :checkout_session_id
      t.bigint :pay_subscription_id
      t.string :subscription_processor_id
      t.datetime :confirmed_at
      t.datetime :acknowledgment_claimed_at
      t.datetime :acknowledgment_sent_at
      t.timestamps
    end

    add_index :billing_consents, :user_id
    add_index :billing_consents, :household_id
    add_index :billing_consents, :checkout_session_id, unique: true
    add_index :billing_consents, :pay_subscription_id, unique: true
  end
end
