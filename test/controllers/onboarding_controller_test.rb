require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get recipes step" do
    get onboarding_recipes_url
    assert_response :success
  end

  test "should save selected starter recipes" do
    assert_difference("Recipe.count", 2) do
      post onboarding_save_recipes_url, params: {
        recipe_ids: ["sheet-pan-fajitas", "spaghetti-bolognese"]
      }
    end
    assert_redirected_to onboarding_pantry_url
  end

  test "should get pantry step" do
    get onboarding_pantry_url
    assert_response :success
  end

  test "should save pantry staples and redirect to root" do
    post onboarding_save_pantry_url, params: {
      staple_names: ["Salt", "Black Pepper", "Olive Oil"]
    }
    assert_redirected_to root_url
  end
end
