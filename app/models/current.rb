class Current < ActiveSupport::CurrentAttributes
  attribute :session, :family_member
  delegate :user, to: :session, allow_nil: true
  delegate :household, to: :user, allow_nil: true
end
