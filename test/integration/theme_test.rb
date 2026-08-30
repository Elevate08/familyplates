require "test_helper"

class ThemeTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @member_one = family_members(:one) # e.g. #3B82F6 (Blue)
    @member_two = family_members(:two) # e.g. #10B981 (Emerald)
    sign_in_as(@member_one)
  end

  test "theme color adapts to active family member" do
    post switch_family_member_url(@member_one), params: { pin: "1234" }
    get recipes_url
    assert_response :success
    assert_includes response.body, "--user-accent: #{@member_one.avatar_color}"

    post switch_family_member_url(@member_two)
    get recipes_url
    assert_response :success
    assert_includes response.body, "--user-accent: #{@member_two.avatar_color}"
  end
end
