module SessionTestHelper
  def sign_in_as(user, family_member: nil)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]

      member = family_member || user.household.family_members.first
      if member
        cookie_jar.signed[:active_family_member_id] = member.id
        cookies["active_family_member_id"] = cookie_jar[:active_family_member_id]
        Current.family_member = member
      end
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
    cookies.delete("active_family_member_id")
    Current.family_member = nil
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
