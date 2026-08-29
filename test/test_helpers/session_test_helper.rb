module SessionTestHelper
  def sign_in_as(member_or_household = nil, family_member: nil)
    member = if family_member.present?
      family_member
    elsif member_or_household.is_a?(FamilyMember)
      member_or_household
    elsif member_or_household.respond_to?(:family_members)
      member_or_household.family_members.find_by(role: "admin") || member_or_household.family_members.first
    else
      FamilyMember.find_by(role: "admin") || FamilyMember.first
    end

    if member
      jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
      jar.signed[:active_family_member_id] = member.id
      cookies["active_family_member_id"] = jar["active_family_member_id"]
      Current.family_member = member
      Current.household = member.household
    end
  end

  def sign_out
    cookies.delete("active_family_member_id")
    Current.family_member = nil
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
