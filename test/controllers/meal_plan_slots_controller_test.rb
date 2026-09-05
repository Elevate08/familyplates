require "test_helper"

class MealPlanSlotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @household = households(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@admin)
  end

  test "should create meal plan slot" do
    assert_difference([ "MealPlanSlot.count", "ActivityEvent.where(event_type: 'meal_plan_slot.created').count" ], 1) do
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
    assert_includes flash[:notice], "Scheduled"
  end

  test "should schedule meal from recipe view with return_to recipe via turbo stream" do
    recipe = recipes(:one)
    target_date = Date.current.beginning_of_week + 4.days
    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_slots_url, params: {
        return_to: "recipe",
        meal_plan_slot: {
          date: target_date,
          meal_type: "lunch",
          recipe_id: recipe.id
        }
      }, as: :turbo_stream
    end
    assert_response :success
    assert_includes @response.body, "recipe_schedule_feedback"
    assert_includes @response.body, "Scheduled"
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

  test "non-admin member should not be able to create meal plan slot" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    assert_no_difference("MealPlanSlot.count") do
      post meal_plan_meal_plan_slots_url(@meal_plan), params: {
        meal_plan_slot: {
          date: Date.current.beginning_of_week + 2.days,
          meal_type: "dinner",
          recipe_id: recipes(:one).id
        }
      }
    end
    assert_redirected_to root_url
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  test "non-admin member should not be able to update meal plan slot" do
    sign_in_as(family_members(:two)) # Mom (role: member)
    slot = meal_plan_slots(:one)

    patch meal_plan_meal_plan_slot_url(@meal_plan, slot), params: {
      meal_plan_slot: { notes: "Should not change" }
    }
    assert_redirected_to root_url
    assert_not_equal "Should not change", slot.reload.notes
  end

  test "non-admin member should not be able to destroy meal plan slot" do
    sign_in_as(family_members(:two)) # Mom (role: member)
    slot = meal_plan_slots(:one)

    assert_no_difference("MealPlanSlot.count") do
      delete meal_plan_meal_plan_slot_url(@meal_plan, slot)
    end
    assert_redirected_to root_url
  end

  # --- Moving a slot -----------------------------------------------------------
  #
  # A move can displace whatever occupies the destination. The controller used to
  # destroy that occupant and only then attempt the update, outside a
  # transaction, so a failure on the second half lost the destination for good.

  test "moving onto an occupied slot replaces it" do
    plan = @household.current_meal_plan
    source = plan.meal_plan_slots.create!(date: plan.week_start_date, meal_type: "lunch", custom_title: "Soup")
    dest = plan.meal_plan_slots.create!(date: plan.week_start_date + 1, meal_type: "lunch", custom_title: "Salad")

    patch meal_plan_meal_plan_slot_url(plan, source), params: {
      meal_plan_slot: { date: (plan.week_start_date + 1).to_s, meal_type: "lunch" }
    }

    assert_nil MealPlanSlot.find_by(id: dest.id), "the displaced slot should be gone"
    assert_equal plan.week_start_date + 1, source.reload.date
    assert_equal "Soup", source.custom_title
  end

  test "a failed move leaves both slots exactly as they were" do
    plan = @household.current_meal_plan
    source = plan.meal_plan_slots.create!(date: plan.week_start_date, meal_type: "lunch", custom_title: "Soup")
    dest = plan.meal_plan_slots.create!(date: plan.week_start_date + 1, meal_type: "lunch", custom_title: "Salad")

    # The failure has to land *after* the destination is destroyed, so the move
    # target must match it exactly and something else must break. A recipe id
    # that does not exist trips the foreign key on the source update. Driven over
    # HTTP so this is a regression test against the old two-step controller
    # rather than a test of the new method's signature.
    patch meal_plan_meal_plan_slot_url(plan, source), params: {
      meal_plan_slot: { date: (plan.week_start_date + 1).to_s, meal_type: "lunch", recipe_id: 999_999 }
    }

    assert MealPlanSlot.exists?(dest.id), "the destination must survive a failed move"
    assert_equal "Salad", dest.reload.custom_title
    assert_equal plan.week_start_date, source.reload.date, "and the source must not have moved"
    assert_equal "lunch", source.meal_type
    assert_nil source.recipe_id
  end

  test "a slot from another household cannot be updated" do
    other = households(:two)
    other_plan = other.meal_plans.create!(week_start_date: Date.new(2026, 3, 2))
    other_slot = other_plan.meal_plan_slots.create!(date: Date.new(2026, 3, 2), meal_type: "dinner", custom_title: "Not Yours")

    patch meal_plan_meal_plan_slot_url(@household.current_meal_plan, other_slot),
          params: { meal_plan_slot: { custom_title: "Hijacked" } }

    assert_response :not_found
    assert_equal "Not Yours", other_slot.reload.custom_title
  end

  test "should create and update leftover slot with leftover_source_slot_id" do
    source_slot = meal_plan_slots(:one)
    target_date = Date.current.beginning_of_week + 4.days

    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_meal_plan_slots_url(@meal_plan), params: {
        meal_plan_slot: {
          date: target_date,
          meal_type: "lunch",
          recipe_id: source_slot.recipe_id,
          is_leftover: true,
          leftover_source_slot_id: source_slot.id
        }
      }
    end

    created_slot = MealPlanSlot.order(:created_at).last
    assert_equal true, created_slot.is_leftover
    assert_equal source_slot.id, created_slot.leftover_source_slot_id

    # Updating with is_leftover: false clears the leftover_source_slot_id
    patch meal_plan_meal_plan_slot_url(@meal_plan, created_slot), params: {
      meal_plan_slot: {
        is_leftover: false
      }
    }
    assert_redirected_to meal_plan_url(@meal_plan)
    created_slot.reload
    assert_equal false, created_slot.is_leftover
    assert_nil created_slot.leftover_source_slot_id
  end
end
