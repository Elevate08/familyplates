# This migration comes from pay (originally 2)
#
# Edited after install: the appliance edition runs every migration but does not
# bundle the pay gem, so the STI backfill is plain SQL rather than
# Pay::Customer/Pay::Merchant. It sets the same type values pay's version did,
# processor by processor; on an appliance the pay_* tables are empty and it
# updates nothing.
class AddPayStiColumns < ActiveRecord::Migration[6.0]
  def change
    add_column :pay_customers, :type, :string
    add_column :pay_charges, :type, :string
    add_column :pay_subscriptions, :type, :string

    rename_column :pay_payment_methods, :type, :payment_method_type
    add_column :pay_payment_methods, :type, :string

    add_column :pay_merchants, :type, :string

    reversible do |dir|
      dir.up { backfill_sti_types }
    end
  end

  private

  def backfill_sti_types
    select_values("SELECT DISTINCT processor FROM pay_customers").each do |processor|
      namespace = "Pay::#{processor.classify}"
      customer_ids = "SELECT id FROM pay_customers WHERE processor = #{quote(processor)}"

      execute "UPDATE pay_customers SET type = #{quote("#{namespace}::Customer")} WHERE processor = #{quote(processor)}"
      execute "UPDATE pay_charges SET type = #{quote("#{namespace}::Charge")} WHERE customer_id IN (#{customer_ids})"
      execute "UPDATE pay_subscriptions SET type = #{quote("#{namespace}::Subscription")} WHERE customer_id IN (#{customer_ids})"
      execute "UPDATE pay_payment_methods SET type = #{quote("#{namespace}::PaymentMethod")} WHERE customer_id IN (#{customer_ids})"
    end

    select_values("SELECT DISTINCT processor FROM pay_merchants").each do |processor|
      execute "UPDATE pay_merchants SET type = #{quote("Pay::#{processor.classify}::Merchant")} WHERE processor = #{quote(processor)}"
    end
  end
end
