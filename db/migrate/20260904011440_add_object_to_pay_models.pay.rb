# This migration comes from pay (originally 20250415151129)
#
# Edited after install: :json instead of Pay::Adapter.json_column_type, so the
# appliance (no pay gem) can run it. See 20260904011438_create_pay_tables.pay.rb.
class AddObjectToPayModels < ActiveRecord::Migration[6.0]
  def change
    add_column :pay_charges, :object, :json
    add_column :pay_customers, :object, :json
    add_column :pay_subscriptions, :object, :json
  end
end
