require "test_helper"

# SA-09, through the real middleware stack and controllers. The stack fixes its
# trusted proxies at boot, so this only means something where the app booted as
# an appliance; the hosted bundle boots as hosted and keeps Rails' default.
# test/lib/trusted_proxies_test.rb covers the logic for both, and
# test/lib/production_boot_test.rb checks what production boots with.
class SpoofedClientAddressTest < ActionDispatch::IntegrationTest
  setup do
    skip "the hosted bundle boots as hosted" if FamilyPlates.saas?
    FamilyPlates.config.reset!
  end

  teardown { FamilyPlates.config.reset! }

  # Thruster on loopback, with the LAN client's address as the last entry.
  def behind_thruster(client, spoofed)
    { "REMOTE_ADDR" => "127.0.0.1", "X-Forwarded-For" => "#{spoofed}, #{client}" }
  end

  test "remote_ip is the address Thruster saw, not a first entry the client made up" do
    get new_session_path, headers: behind_thruster("192.168.1.50", "203.0.113.50")

    assert_equal "192.168.1.50", request.remote_ip
  end

  test "a rotating spoofed address does not dodge the per-IP sign-in limit" do
    (LoginThrottling::MAX_ATTEMPTS + 1).times do |i|
      post session_path, params: { email: "guess#{i}@example.com", password: "bad" },
           headers: behind_thruster("192.168.1.50", "203.0.113.#{i + 1}")
    end

    assert_redirected_to new_session_path
    assert_equal "Too many sign-in attempts. Please wait a few minutes and try again.", flash[:alert]
  end

  test "a rotating spoofed address does not dodge the per-IP PIN limit" do
    others = 3.times.map do |i|
      households(:one).family_members.create!(
        name: "Organizer #{i}", role: "admin", pin: "5678",
        avatar_color: FamilyMember::AVATAR_COLORS[i + 2], avatar_icon: "star"
      )
    end
    targets = [ family_members(:one) ] + others

    (PinThrottling::MAX_ATTEMPTS + 1).times do |i|
      post set_profile_url(targets[i % targets.size]), params: { pin: "9999" },
           headers: behind_thruster("192.168.1.50", "203.0.113.#{i + 1}")
    end

    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]
  end

  test "a client cannot spend another address's sign-in budget" do
    (LoginThrottling::MAX_ATTEMPTS + 1).times do |i|
      post session_path, params: { email: "guess#{i}@example.com", password: "bad" },
           headers: behind_thruster("192.168.1.50", "192.168.1.99")
    end

    # The victim's own address is untouched.
    post session_path, params: { email: "victim@example.com", password: "bad" },
         headers: behind_thruster("192.168.1.99", "192.168.1.99")

    assert_response :unprocessable_entity
  end

  test "a session records the address Thruster saw" do
    user = User.create!(email: "parent@example.com", password: "valid-password123")

    post session_path, params: { email: user.email, password: "valid-password123" },
         headers: behind_thruster("192.168.1.50", "203.0.113.50")

    assert_equal "192.168.1.50", Session.order(:created_at).last.ip_address
  end
end
