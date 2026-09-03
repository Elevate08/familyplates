require "application_system_test_case"

# The profile picker and the PIN modals are the app's entire authentication
# surface, and they run on inline scripts - which is exactly what the CSP work
# broke twice without any test noticing. Signing in through the real UI also
# exercises the digest comparison and the throttle.
class AuthenticationTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "a PIN-less member signs in with one tap" do
    visit select_profile_path
    click_on @member.name

    assert_no_current_path select_profile_path, wait: 5
  end

  test "an organizer must enter a PIN, and the modal opens" do
    visit select_profile_path
    click_on @admin.name

    # The modal is driven by an inline script; a CSP that refuses it leaves this
    # button doing nothing at all, which is what happened in review.
    assert_selector "input[name='pin']", visible: true, wait: 5
    assert_text @admin.name

    find("input[name='pin']").fill_in(with: "1234")
    find("input[name='pin']").native.send_keys(:enter)

    assert_no_current_path select_profile_path, wait: 5
  end

  test "a wrong PIN is refused and says so" do
    visit select_profile_path
    click_on @admin.name

    find("input[name='pin']", wait: 5).fill_in(with: "9999")
    find("input[name='pin']").native.send_keys(:enter)

    assert_text "Incorrect", wait: 5
  end

  test "the PIN modal can be dismissed" do
    visit select_profile_path
    click_on @admin.name
    assert_selector "input[name='pin']", visible: true, wait: 5

    click_on "Cancel"

    assert_no_selector "input[name='pin']", visible: true, wait: 3
  end

  test "a flash message can be dismissed" do
    # Signing in produces a welcome flash; its close button was an inline
    # onclick until the CSP work converted it to a Stimulus action.
    visit select_profile_path
    click_on @member.name

    assert_selector "#flash-messages [role='alert']", wait: 5
    within("#flash-messages") { find("button").click }

    assert_no_selector "#flash-messages [role='alert']", wait: 3
  end
end
