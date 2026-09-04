require "test_helper"

class ActivityEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @recipe = recipes(:one)
    sign_in_as(@admin)
    ActivityEvent.track!(
      household: households(:one),
      actor: @admin,
      event_type: "recipe.created",
      target: @recipe
    )
  end

  test "shows meaningful activity with the family member who performed it" do
    get activity_history_path

    assert_response :success
    assert_includes response.body, "Dad created recipe #{@recipe.title}"
    assert_select "time"
  end

  test "is available to a household member" do
    sign_in_as(family_members(:two))

    get activity_history_path

    assert_response :success
  end
end
