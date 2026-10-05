class AddPaidDiscountToBillingConsents < ActiveRecord::Migration[8.1]
  # The discount Stripe applied to the first payment, so the acknowledgment
  # can say why the amount paid differs from the plan price.
  def change
    add_column :billing_consents, :paid_discount_minor_units, :integer
  end
end
