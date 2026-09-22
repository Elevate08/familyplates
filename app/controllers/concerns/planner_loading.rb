module PlannerLoading
  private

  def prepare_planner_preloads(plan = @meal_plan)
    household = plan&.household || current_household
    return unless household && plan

    @recipes = household.recipes.alphabetical.includes(image_attachment: :blob).to_a
    @recipes_map = @recipes.each_with_object({}) do |recipe, recipes_map|
      recipes_map[recipe.id] = {
        title: recipe.title,
        image_url: recipe.display_image_url,
        tags: recipe.tag_list,
        total_time: recipe.total_time
      }
    end
    @family_members = household.family_members.order(:name).to_a
    @slots_by_key = plan.meal_plan_slots.includes(:recipe, :family_member, :leftover_source_slot).index_by { |slot| [ slot.date, slot.meal_type ] }
    @leftover_sources = plan.preloaded_leftover_sources
  end

  def find_meal_plan!(identifier)
    current_household.meal_plans.find_by(number: identifier) || current_household.meal_plans.find_by(id: identifier) ||
      raise(ActiveRecord::RecordNotFound, "Couldn't find MealPlan with 'id'=#{identifier}")
  end
end
