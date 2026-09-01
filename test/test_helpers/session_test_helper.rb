module SessionTestHelper
  COOKIE_NAME = "active_family_member_id".freeze

  # Signs in the way a real visitor does — POST /set_profile/:id — rather than
  # forging the cookie. Tests then exercise the PIN check, the signed cookie and
  # whatever else the profile entry path grows (throttling, audit logging), so a
  # change that breaks sign-in fails the suite instead of being papered over.
  #
  # Admin profiles need a PIN. Pass one explicitly to test a specific value;
  # otherwise the member's own PIN is used, which is what a test setup means.
  def sign_in_as(member, pin: nil)
    unless member.is_a?(FamilyMember)
      raise ArgumentError, "sign_in_as expects a FamilyMember, got #{member.class}: #{member.inspect}"
    end

    post set_profile_path(member), params: { pin: pin || member.pin }

    unless signed_in_as?(member)
      flunk <<~MESSAGE
        sign_in_as(#{member.name.inspect}) did not sign in.
        Expected the #{COOKIE_NAME} cookie to hold id #{member.id}, got #{active_family_member_id.inspect}.
        Last response: #{response.status} #{response.location}
        Flash: #{flash.to_hash.inspect}
      MESSAGE
    end

    member
  end

  def sign_out
    delete session_path
    return if active_family_member_id.nil?

    flunk "sign_out left #{COOKIE_NAME} set to #{active_family_member_id.inspect}"
  end

  def signed_in_as?(member)
    active_family_member_id == member.id
  end

  # Integration tests get a Rack::Test cookie jar, which has no #signed, so
  # unwrap the signed value through a jar that shares the app's secret.
  def active_family_member_id
    raw = cookies[COOKIE_NAME]
    return nil if raw.blank?

    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, COOKIE_NAME => raw)
    jar.signed[COOKIE_NAME]
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
