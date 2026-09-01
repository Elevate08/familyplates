require "test_helper"

# The 4-digit admin PIN is the only credential in the app, over a 10,000-value
# keyspace, and /set_profile is reachable with no session at all. The removed
# SessionsController carried "rate_limit to: 10, within: 3.minutes"; neither
# replacement entry path inherited anything.
class PinThrottlingTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  def guess(member, pin: "9999", headers: {})
    post set_profile_url(member), params: { pin: pin }, headers: headers
  end

  test "an unauthenticated attacker is cut off after the attempt budget" do
    PinThrottling::MAX_ATTEMPTS.times do
      guess(@admin)
      assert_equal "Incorrect 4-digit PIN for #{@admin.name}.", flash[:alert]
    end

    guess(@admin)

    assert_redirected_to select_profile_url
    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]
  end

  test "a throttled response does not reveal whether the PIN was correct" do
    (PinThrottling::MAX_ATTEMPTS + 1).times { guess(@admin) }
    wrong_pin_response = [ response.status, response.location, flash[:alert] ]

    guess(@admin, pin: @admin.pin)

    assert_equal wrong_pin_response, [ response.status, response.location, flash[:alert] ]
    assert_nil active_family_member_id, "the correct PIN must not sign in while throttled"
  end

  test "throttling one profile does not lock out another" do
    other_admin = households(:one).family_members.create!(
      name: "Second Organizer", role: "admin", pin: "5678", avatar_color: "#8B5CF6", avatar_icon: "star"
    )

    (PinThrottling::MAX_ATTEMPTS + 1).times { guess(@admin) }
    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]

    # Same IP, so the per-IP budget is spent too — a different IP is not.
    post set_profile_url(other_admin), params: { pin: "5678" },
         headers: { "REMOTE_ADDR" => "203.0.113.7" }

    assert signed_in_as?(other_admin)
  end

  test "the per-IP budget stops one host working through every profile" do
    others = 3.times.map do |i|
      households(:one).family_members.create!(
        name: "Organizer #{i}", role: "admin", pin: "5678",
        avatar_color: FamilyMember::AVATAR_COLORS[i + 2], avatar_icon: "star"
      )
    end

    attempts = 0
    ([ @admin ] + others).cycle do
      break if attempts > PinThrottling::MAX_ATTEMPTS
      guess(_1)
      attempts += 1
    end

    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert],
      "spreading guesses across profiles from one host must still be throttled"
  end

  test "PIN-less member switching is never throttled" do
    (PinThrottling::MAX_ATTEMPTS * 3).times do
      post set_profile_url(@member)
      assert signed_in_as?(@member)
    end
  end

  test "the switch endpoint shares the budget with profile selection" do
    sign_in_as(@member)

    PinThrottling::MAX_ATTEMPTS.times { guess(@admin) }

    post switch_family_member_url(@admin), params: { pin: @admin.pin }

    assert_redirected_to select_profile_url
    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]
    assert signed_in_as?(@member), "the throttled switch must not have taken effect"
  end

  test "throttling is logged without any PIN material" do
    logged = +""
    original = Rails.logger
    Rails.logger = Logger.new(StringIO.new(logged))

    begin
      (PinThrottling::MAX_ATTEMPTS + 1).times { guess(@admin, pin: "8642") }
    ensure
      Rails.logger = original
    end

    # Only our own messages, with Logger's timestamp prefix stripped. Searching
    # the raw log for four digits matches microsecond timestamps and record ids
    # by coincidence - "18:30:27.238642" contains "8642" - which made an earlier
    # version of this assertion fail roughly one run in twenty-five.
    auth_messages = logged.lines.filter_map { |line| line[/\[auth\].*/]&.strip }

    assert auth_messages.any? { |m| m.start_with?("[auth] pin_failure profile_id=#{@admin.id} ") }
    assert auth_messages.any? { |m| m.start_with?("[auth] pin_throttled ") && m.include?("profile_id=#{@admin.id} ") }

    # Every auth message must be nothing but known key=value pairs, so anything
    # unexpected - a PIN above all - fails regardless of what digits it happens
    # to be made of.
    permitted = /\A\[auth\] (?:pin_failure|pin_throttled) (?:(?:limit|profile_id|ip|path)=\S+ ?)+\z/
    auth_messages.each do |message|
      assert_match(permitted, message, "unexpected content in an auth log line")
    end

    assert auth_messages.none? { |m| m.include?("8642") }, "a submitted PIN must never reach the log"
    assert auth_messages.none? { |m| m.include?(@admin.pin) }, "a stored PIN must never reach the log"
  end
end
