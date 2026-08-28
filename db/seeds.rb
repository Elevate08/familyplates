puts "🌱 Seeding FamilyPlates demo kitchen..."

household = Household.find_or_create_by!(name: "The Spencer Family")

user = household.users.find_or_initialize_by(email_address: "family@mealhub.local")
user.password = "password123"
user.password_confirmation = "password123"
user.save!

dad = household.family_members.find_or_create_by!(name: "Dad") do |m|
  m.avatar_color = "#3B82F6" # Ocean Blue
  m.avatar_icon = "chef-hat"
  m.role = "admin"
  m.pin = "1234"
end
dad.update!(pin: "1234", avatar_color: "#3B82F6") if dad.pin.blank?

mom = household.family_members.find_or_create_by!(name: "Mom") do |m|
  m.avatar_color = "#EC4899" # Berry Pink
  m.avatar_icon = "utensils"
  m.role = "admin"
  m.pin = "5678"
end
mom.update!(pin: "5678", avatar_color: "#EC4899") if mom.pin.blank?

maya = household.family_members.find_or_create_by!(name: "Maya (10)") do |m|
  m.avatar_color = "#10B981" # Sage Emerald
  m.avatar_icon = "smile"
  m.role = "member"
end

leo = household.family_members.find_or_create_by!(name: "Leo (7)") do |m|
  m.avatar_color = "#F59E0B" # Amber Golden
  m.avatar_icon = "sparkles"
  m.role = "member"
end

# Seed Pantry Staples
PantryItem::DEFAULT_STAPLES.each do |staple|
  household.pantry_items.find_or_create_by!(name: staple[:name]) do |item|
    item.aisle_category = staple[:aisle_category]
    item.emoji = staple[:emoji]
    item.is_staple = true
  end
end

# Seed Starter Recipes
config = YAML.load_file(Rails.root.join("config/starter_recipes.yml"))
starters = config["starter_recipes"] || []

created_recipes = []
starters.each do |s|
  recipe = household.recipes.find_or_create_by!(title: s["title"]) do |r|
    r.description = s["description"]
    r.prep_time = s["prep_time"]
    r.cook_time = s["cook_time"]
    r.servings = s["servings"] || 4
    r.image_url = s["image_url"]
    r.instructions = s["instructions"]
    r.tags = Array(s["tags"]).join(", ")
  end
  recipe.update!(image_url: s["image_url"]) if recipe.image_url.blank?

  if recipe.recipe_ingredients.empty?
    Array(s["ingredients"]).each do |ing|
      recipe.recipe_ingredients.create!(
        raw_text: ing["raw_text"],
        name: ing["name"],
        quantity: ing["quantity"],
        unit: ing["unit"],
        aisle_category: ing["aisle_category"] || "Other"
      )
    end
  end

  created_recipes << recipe
end

# Seed Current Week Meal Plan
week_start = Date.current.beginning_of_week
plan = household.current_meal_plan(week_start)

cooks = [ dad, mom, dad, maya, mom, leo, dad ]

plan.days.each_with_index do |day, idx|
  recipe = created_recipes[idx % created_recipes.size]
  cook = cooks[idx % cooks.size]

  # Dinner
  slot = plan.meal_plan_slots.find_or_initialize_by(date: day, meal_type: "dinner")
  slot.recipe = recipe
  slot.family_member = cook
  slot.notes = "Family dinner night"
  slot.save!

  # Lunch
  if idx.even?
    l_slot = plan.meal_plan_slots.find_or_initialize_by(date: day, meal_type: "lunch")
    l_slot.custom_title = "Leftover #{recipe.title.truncate(20)}"
    l_slot.save!
  end

  # Breakfast
  if idx.zero? || idx == 6
    b_slot = plan.meal_plan_slots.find_or_initialize_by(date: day, meal_type: "breakfast")
    b_slot.custom_title = "Pancake & Fruit Morning"
    b_slot.family_member = dad
    b_slot.save!
  end
end

puts "✅ Seed completed!"
puts "👉 Log in as: family@mealhub.local (Password: password123)"
puts "👉 Dad PIN: 1234 | Mom PIN: 5678 | Maya & Leo: No PIN needed"
