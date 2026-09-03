require "application_system_test_case"

# The first-boot wizard was walked by hand four times during this branch, and
# each pass found something: a PIN prefilled with a value published in this
# repository, a profile switcher that silently did nothing because its script was
# CSP-blocked, a confirm dialog that never closed, and starter recipes rendering
# a placeholder instead of their images.
class OnboardingTest < ApplicationSystemTestCase
  setup { Household.destroy_all }

  test "a household can be set up from nothing" do
    visit root_path
    assert_selector "input[name='admin_member[pin]']", wait: 5

    fill_in "household[name]", with: "The Testers"
    fill_in "admin_member[name]", with: "Head Chef"
    fill_in "admin_member[pin]", with: "7391"
    click_on "Create Kitchen & Continue to Family Roster →"

    assert_text "Family Kitchen Roster", wait: 5

    assert_equal 1, Household.count
    admin = FamilyMember.find_by(role: "admin")
    assert admin.verify_pin("7391")
    assert_nil admin.pin, "the PIN must not be readable off the record"
  end

  test "the setup form never suggests a PIN" do
    visit onboarding_family_path

    assert_no_text "1234"
    assert_empty find("input[name='admin_member[pin]']").value,
      "a prefilled PIN becomes the real one for anyone who clicks through"
  end

  test "setup refuses to continue without a PIN" do
    visit onboarding_family_path

    fill_in "household[name]", with: "No PIN Kitchen"
    fill_in "admin_member[name]", with: "Chef"
    click_on "Create Kitchen & Continue to Family Roster →"

    assert_equal 0, Household.count, "a blank PIN must not create a household"
  end
end
