require "test_helper"

# The sign-in helper is load-bearing for every authorization test in the suite.
# If it ever went back to silently doing nothing, those tests would keep passing
# while asserting against an anonymous session, so its failure modes are pinned
# here rather than left to trust.
class SessionTestHelperTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "signs an admin in through the real profile entry path" do
    assert_nil active_family_member_id

    sign_in_as(@admin)

    assert_equal @admin.id, active_family_member_id
    assert signed_in_as?(@admin)
  end

  test "signs a PIN-less member in without a PIN" do
    assert_not @member.requires_pin?

    sign_in_as(@member)

    assert_equal @member.id, active_family_member_id
  end

  test "accepts an explicit PIN" do
    sign_in_as(@admin, pin: @admin.pin)

    assert_equal @admin.id, active_family_member_id
  end

  test "fails the test rather than continuing anonymously when the PIN is wrong" do
    error = assert_raises(Minitest::Assertion) { sign_in_as(@admin, pin: "9999") }

    assert_match(/did not sign in/, error.message)
    assert_nil active_family_member_id, "no session should have been established"
  end

  test "rejects anything that is not a family member" do
    assert_raises(ArgumentError) { sign_in_as(households(:one)) }
    assert_raises(ArgumentError) { sign_in_as(nil) }
  end

  test "sign_out clears the session" do
    sign_in_as(@admin)
    assert_equal @admin.id, active_family_member_id

    sign_out

    assert_nil active_family_member_id
  end
end
