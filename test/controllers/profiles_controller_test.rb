require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    sign_in_as(@admin)
  end

  test "should get select" do
    get select_profile_url
    assert_response :success
  end

  test "profile picker stays in creation order when UUIDs do not sort that way" do
    household = households(:one)
    older = household.family_members.create!(
      id: "ffffffff-ffff-4fff-bfff-ffffffffffff", name: "Older Profile", created_at: 2.days.ago
    )
    newer = household.family_members.create!(
      id: "00000000-0000-4000-8000-000000000000", name: "Newer Profile", created_at: 1.day.ago
    )

    get select_profile_url

    cards = css_select("div.grid > div.group").map { |card| card.text.squish }
    older_position = cards.index { |card| card.include?(older.name) }
    newer_position = cards.index { |card| card.include?(newer.name) }
    assert_operator older_position, :<, newer_position
  end

  test "should set non-admin profile without pin" do
    member = family_members(:two)
    post set_profile_url(member)

    assert_redirected_to root_url
    assert_not_nil cookies[:active_family_member_id]
  end

  test "should set admin profile with valid pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "1234" }

    assert_redirected_to root_url
    assert_not_nil cookies[:active_family_member_id]
  end

  test "should reject admin profile with invalid pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "9999" }

    assert_redirected_to select_profile_url(pin_member_id: admin.id)
    assert_equal "Incorrect 4-digit PIN for #{admin.name}.", flash[:alert]
  end

  test "should reject admin profile with blank pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "" }

    assert_redirected_to select_profile_url(pin_member_id: admin.id)
    assert_equal "This profile is protected by a PIN.", flash[:alert]
  end

  test "should redirect to select profile if no active profile selected" do
    cookies.delete("active_family_member_id")
    Current.family_member = nil

    get root_url
    assert_redirected_to select_profile_url
  end

  # --- Post-sign-in redirect --------------------------------------------------
  #
  # require_authentication stores request.url for any verb, and profiles#set now
  # consumes it (it used to always go to root_path). The redirect is a GET, so a
  # stored POST target lands on a route that does not accept GET.

  test "a stored GET destination is returned to after sign-in" do
    sign_out

    get recipes_url
    assert_redirected_to select_profile_url

    post set_profile_url(@admin), params: { pin: "1234" }

    assert_redirected_to recipes_url
    follow_redirect!
    assert_response :success
  end

  test "an expired non-GET request does not become a dead redirect target" do
    sign_out

    post meal_plan_slots_url, params: {
      meal_plan_slot: { date: Date.current.to_s, meal_type: "dinner", custom_title: "Fish Tacos" }
    }
    assert_redirected_to select_profile_url
    assert_nil session[:return_to_after_authenticating], "a POST target must not be stored"

    post set_profile_url(@admin), params: { pin: "1234" }

    assert_redirected_to root_url

    # root redirects on to the current meal plan, so follow until it settles -
    # the point is that sign-in lands somewhere real rather than on a 404.
    3.times { break unless response.redirect?; follow_redirect! }
    assert_response :success
  end
end
