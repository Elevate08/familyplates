module SessionTestHelper
  COOKIE_NAME = "active_family_member_id".freeze

  # Signs in the way a real visitor does — POST /set_profile/:id — rather than
  # forging the cookie. Tests then exercise the PIN check, the signed cookie and
  # whatever else the profile entry path grows (throttling, audit logging), so a
  # change that breaks sign-in fails the suite instead of being papered over.
  #
  # The PIN every admin fixture is seeded with. It cannot be read back off a
  # record any more - only a digest is stored - so a caller that needs a
  # different PIN has to say so.
  FIXTURE_PIN = "1234".freeze

  # Admin profiles need a PIN. Pass one explicitly to test a specific value;
  # otherwise the fixture PIN is used, which is what a test setup means.
  def sign_in_as(member, pin: nil)
    unless member.is_a?(FamilyMember)
      raise ArgumentError, "sign_in_as expects a FamilyMember, got #{member.class}: #{member.inspect}"
    end

    post set_profile_path(member), params: { pin: pin || FIXTURE_PIN }

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

  def signed_cookie(key)
    raw = cookies[key.to_s]
    return nil if raw.blank?

    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, key.to_s => raw)
    jar.signed[key.to_s]
  end

  # Integration tests get a Rack::Test cookie jar, which has no #signed, so
  # unwrap the signed value through a jar that shares the app's secret.
  def active_family_member_id
    signed_cookie(COOKIE_NAME)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
