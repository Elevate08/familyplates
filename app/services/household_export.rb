class HouseholdExport
  def self.call(household)
    new(household).call
  end

  def initialize(household)
    @household = household
  end

  def call
    {
      export_version: 1,
      exported_at: Time.current.iso8601,
      household: @household.slice("id", "name", "created_at", "onboarded_at"),
      family_members: @household.family_members.includes(:user).order(:created_at, :id).map do |member|
        member.slice("id", "name", "role", "avatar_color", "avatar_icon", "created_at").merge(
          "email" => member.user&.email
        )
      end,
      recipes: @household.recipes.includes(:recipe_ingredients).order(:created_at, :id).map do |recipe|
        recipe.slice("id", "number", "title", "description", "instructions", "tags", "meal_types", "created_at").merge(
          "ingredients" => recipe.recipe_ingredients.map { |ingredient| ingredient.slice("name", "quantity", "unit", "raw_text") }
        )
      end,
      pantry_items: @household.pantry_items.order(:created_at, :id).map { |item| item.slice("id", "name", "aisle_category", "is_staple", "emoji", "created_at") },
      meal_plans: @household.meal_plans.includes(meal_plan_slots: :recipe).order(:week_start_date).map do |plan|
        plan.slice("id", "number", "week_start_date", "created_at").merge(
          "slots" => plan.meal_plan_slots.order(:date, :meal_type).map do |slot|
            slot.slice("id", "date", "meal_type", "custom_title", "is_leftover", "created_at").merge("recipe_id" => slot.recipe_id)
          end
        )
      end
    }
  end
end
