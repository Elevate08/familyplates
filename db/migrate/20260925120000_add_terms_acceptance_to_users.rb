class AddTermsAcceptanceToUsers < ActiveRecord::Migration[8.1]
  # Proof of consent to the hosted Terms of Service: which version, and when.
  # Null for appliance users, who never see the terms.
  def change
    add_column :users, :terms_accepted_at, :datetime
    add_column :users, :terms_version, :string
  end
end
