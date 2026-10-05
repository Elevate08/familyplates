module User::Billing
  extend ActiveSupport::Concern

  included do
    # Deleting the user leaves these households with no billing owner, matching
    # the foreign key's on_delete: :nullify, rather than blocking the deletion.
    has_many :billing_owned_households, class_name: "Household", foreign_key: :billing_owner_user_id,
      inverse_of: :billing_owner, dependent: :nullify
  end
end
