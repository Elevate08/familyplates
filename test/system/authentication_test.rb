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

  # @card-17.1
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

  # SA-05: Back after signing out must not show the household's pages. Sign Out stays a Turbo form on
  # purpose: Turbo clears its snapshot cache after a form submission (turbo-rails 2.0.23), whereas a
  # plain page load lets Chromium serve the page from its HTTP cache on Back, because Chrome 127+
  # only partly honours Clear-Site-Data "cache" for back/forward navigations (tried: it fails here).
  test "Back after signing out does not show the household's pages" do
    sign_in_as(@member)
    visit grocery_list_path
    # Reach more pages through Turbo, which snapshots each page when it is left
    within("nav") { click_on "Recipe Box" }
    assert_text recipes(:one).title
    within("nav") { click_on "Grocery List" }
    assert_current_path grocery_list_path
    within("nav") { click_on "Recipe Box" }
    assert_text recipes(:one).title

    find("button[title='Active Profile & Kitchen Settings']").click
    click_button "Sign Out"
    assert_current_path select_profile_path, wait: 5

    # Each Back asks the server, which no longer knows this browser.
    2.times do
      page.go_back
      # A restored page would stay at its own address with its content
      assert_current_path select_profile_path, wait: 5
      assert_no_text recipes(:one).title, wait: 0
    end
  end
end
