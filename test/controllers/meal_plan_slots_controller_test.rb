require "test_helper"

class MealPlanSlotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@user)
  end

  test "should create meal plan slot" do
    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_meal_plan_slots_url(@meal_plan), params: {
        meal_plan_slot: {
          date: Date.current.beginning_of_week + 2.days,
          meal_type: "dinner",
          recipe_id: recipes(:one).id,
          family_member_id: family_members(:one).id
        }
      }
    end
    assert_redirected_to meal_plan_url(@meal_plan)
  end

  test "should create meal plan slot via turbo stream" do
    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_meal_plan_slots_url(@meal_plan), params: {
        meal_plan_slot: {
          date: Date.current.beginning_of_week + 2.days,
          meal_type: "breakfast",
          recipe_id: recipes(:one).id
        }
      }, as: :turbo_stream
    end
    assert_response :success
    assert_match(/turbo-stream/, response.media_type)
  end

  test "should schedule meal from recipe view with return_to recipe" do
    recipe = recipes(:one)
    target_date = Date.current.beginning_of_week + 3.days
    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_slots_url, params: {
        return_to: "recipe",
        meal_plan_slot: {
          date: target_date,
          meal_type: "lunch",
          recipe_id: recipe.id
        }
      }
    end
    assert_redirected_to recipe_url(recipe)
  end

  test "should update meal plan slot notes" do
    slot = meal_plan_slots(:one)
    patch meal_plan_meal_plan_slot_url(@meal_plan, slot), params: {
      meal_plan_slot: { notes: "Extra spicy" }
    }
    assert_redirected_to meal_plan_url(@meal_plan)
    assert_equal "Extra spicy", slot.reload.notes
  end

  test "should modify planned meal scheduled_time override" do
    slot = meal_plan_slots(:one)
    patch meal_plan_meal_plan_slot_url(@meal_plan, slot), params: {
      meal_plan_slot: { scheduled_time: "19:45" }
    }
    assert_redirected_to meal_plan_url(@meal_plan)
    assert_equal "19:45", slot.reload.scheduled_time
  end

  test "should modify planned meal recipe, custom title, and cook" do
    slot = meal_plan_slots(:one)
    other_member = family_members(:two)

    patch meal_plan_meal_plan_slot_url(@meal_plan, slot), params: {
      meal_plan_slot: {
        recipe_id: "",
        custom_title: "Taco Tuesday Night",
        family_member_id: other_member.id,
        notes: "Serve with guacamole"
      }
    }

    assert_redirected_to meal_plan_url(@meal_plan)
    slot.reload
    assert_nil slot.recipe_id
    assert_equal "Taco Tuesday Night", slot.custom_title
    assert_equal other_member.id, slot.family_member_id
    assert_equal "Serve with guacamole", slot.notes
  end

  test "should reschedule meal plan slot to different date and meal type" do
    slot = meal_plan_slots(:one)
    new_date = @meal_plan.week_start_date + 4.days

    patch meal_plan_meal_plan_slot_url(@meal_plan, slot), params: {
      meal_plan_slot: {
        date: new_date,
        meal_type: "breakfast"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.media_type)
    slot.reload
    assert_equal new_date, slot.date
    assert_equal "breakfast", slot.meal_type
  end

  test "should destroy meal plan slot via turbo stream" do
    slot = meal_plan_slots(:one)
    assert_difference("MealPlanSlot.count", -1) do
      delete meal_plan_meal_plan_slot_url(@meal_plan, slot), as: :turbo_stream
    end
    assert_response :success
    assert_match(/turbo-stream/, response.media_type)
  end

  test "should destroy meal plan slot" do
    slot = meal_plan_slots(:one)
    assert_difference("MealPlanSlot.count", -1) do
      delete meal_plan_meal_plan_slot_url(@meal_plan, slot)
    end
    assert_redirected_to meal_plan_url(@meal_plan)
  end
end
