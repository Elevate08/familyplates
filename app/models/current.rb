class Current < ActiveSupport::CurrentAttributes
  attribute :household, :family_member, :user, :session, :platform_admin, :platform_admin_session
end
