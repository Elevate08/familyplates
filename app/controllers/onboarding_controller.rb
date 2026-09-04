class OnboardingController < ApplicationController
  WIZARD_STEPS_AFTER_SETUP = %i[members add_member remove_member recipes save_recipes pantry save_pantry complete].freeze

  allow_unauthenticated_access only: %i[family save_family]
  allow_unconfigured_access only: %i[family save_family]
  before_action :ensure_household_unconfigured, only: %i[family save_family]
  # save_family signs the new organizer in, so the rest of the wizard runs as an
  # authenticated admin on a first boot and is closed to everyone else after it.
  before_action :require_admin, only: WIZARD_STEPS_AFTER_SETUP
  before_action :load_starter_recipes, only: %i[recipes save_recipes]

  # Step 1: Kitchen & Family Setup
  def family
    @household = Household.new(
      name: "",
      breakfast_time: "08:00",
      lunch_time: "12:30",
      dinner_time: "18:00"
    )
    @admin_member = FamilyMember.new(
      role: "admin",
      avatar_color: "#3B82F6",
      avatar_icon: "chef-hat"
    )
  end

  def save_family
    ActiveRecord::Base.transaction do
      @household = Household.new(household_params)
      @household.save!

      initial_name = admin_member_params[:name].presence || "Head Chef"
      initial_pin = admin_member_params[:pin]
      initial_color = admin_member_params[:avatar_color].presence || "#3B82F6"
      initial_icon = admin_member_params[:avatar_icon].presence || "chef-hat"

      @admin_member = @household.family_members.create!(
        name: initial_name,
        role: "admin",
        avatar_color: initial_color,
        avatar_icon: initial_icon,
        pin: initial_pin
      )

      start_new_session_for(@admin_member)

      redirect_to onboarding_members_path, notice: "Welcome to FamilyPlates! Your kitchen is created."
    end
  rescue ActiveRecord::RecordInvalid => e
    @admin_member ||= FamilyMember.new(admin_member_params)
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :family, status: :unprocessable_entity
  end

  # Step 2: Family Roster
  def members
    @family_members = current_household.family_members.order(:created_at, :id)
    @new_member = current_household.family_members.build(
      role: "member",
      avatar_color: (FamilyMember::AVATAR_COLORS - @family_members.pluck(:avatar_color)).first || FamilyMember::AVATAR_COLORS.sample,
      avatar_icon: %w[utensils heart star smile flame sparkles].sample
    )
  end

  def add_member
    @new_member = current_household.family_members.build(family_member_params)

    if @new_member.save
      existing_colors = current_household.family_members.pluck(:avatar_color)
      @fresh_member = current_household.family_members.build(
        role: "member",
        avatar_color: (FamilyMember::AVATAR_COLORS - existing_colors).first || FamilyMember::AVATAR_COLORS.sample,
        avatar_icon: %w[utensils heart star smile flame sparkles award].sample
      )
      respond_to do |format|
        format.html { redirect_to onboarding_members_path, notice: "#{@new_member.name} was added to the family roster! 👩‍🍳" }
        format.turbo_stream
      end
    else
      @family_members = current_household.family_members.where.not(id: nil).order(:created_at, :id)
      flash.now[:alert] = @new_member.errors.full_messages.to_sentence
      render :members, status: :unprocessable_entity
    end
  end

  def remove_member
    @member = current_household.family_members.find(params[:id])

    if @member.admin? && current_household.family_members.where(role: "admin").count <= 1
      redirect_to onboarding_members_path, alert: "You cannot remove the primary kitchen organizer."
    else
      @member.destroy
      redirect_to onboarding_members_path, notice: "#{@member.name} was removed."
    end
  end

  # Step 3: Starter Recipes
  def recipes
    @selected_recipe_ids = @starter_recipes.map { |r| r["id"] }
  end

  def save_recipes
    selected_ids = Array(params[:recipe_ids]).map(&:to_s)

    created = []

    ActiveRecord::Base.transaction do
      RecipeIngredient.without_aisle_sync do
      @starter_recipes.each do |starter|
        next unless selected_ids.include?(starter["id"])

        recipe = current_household.recipes.find_or_create_by!(title: starter["title"]) do |r|
          r.description = starter["description"]
          r.prep_time = starter["prep_time"]
          r.cook_time = starter["cook_time"]
          r.servings = starter["servings"] || 4
          r.image_url = starter["image_url"]
          r.instructions = starter["instructions"]
          r.tags = Array(starter["tags"]).join(", ")
        end

        if recipe.recipe_ingredients.empty?
          Array(starter["ingredients"]).each do |ing|
            recipe.recipe_ingredients.create!(
              raw_text: ing["raw_text"],
              name: ing["name"],
              quantity: ing["quantity"],
              unit: ing["unit"],
              aisle_category: ing["aisle_category"].presence
            )
          end
        end

        created << recipe
      end
      end
    end

    # One resync per distinct ingredient name, after every starter recipe has
    # landed, rather than one per ingredient as each was created.
    created.each(&:resync_aisle_mappings!)

    redirect_to onboarding_pantry_path, notice: "Great picks! Now let's confirm what you keep on hand."
  end

  # Step 4: Pantry Staples
  def pantry
    @default_staples = PantryItem::DEFAULT_STAPLES
  end

  def save_pantry
    selected_staple_names = Array(params[:staple_names]).map(&:to_s)

    ActiveRecord::Base.transaction do
      PantryItem::DEFAULT_STAPLES.each do |staple|
        is_selected = selected_staple_names.include?(staple[:name])
        item = current_household.pantry_items.find_or_initialize_by(name: staple[:name])

        # Seed the defaults only when creating. This step used to assign them
        # unconditionally, so re-running the wizard reset a household's
        # hand-picked category and icon back to the DEFAULT_STAPLES values. Only
        # the checkbox is the user's answer on this screen.
        if item.new_record?
          item.aisle_category = staple[:aisle_category]
          item.emoji = staple[:emoji]
        end

        item.is_staple = is_selected
        item.save!
      end
    end

    redirect_to onboarding_complete_path
  end

  # Step 5: Completion & Celebration
  def complete
    @members_count = current_household.family_members.count
    @recipes_count = current_household.recipes.count
    @staples_count = current_household.pantry_items.staples.count
    @current_meal_plan = current_household.current_meal_plan

    current_household.mark_onboarded! unless current_household.onboarded?
  end

  private

  def ensure_household_unconfigured
    if FamilyPlates.config.hosted?
      if Current.user.nil?
        redirect_to new_signup_path, alert: "In hosted mode, please sign up to create a household." and return
      elsif current_household&.onboarded?
        redirect_to root_path, alert: "Your family kitchen is already set up." and return
      elsif current_household.present?
        redirect_to onboarding_recipes_path and return
      else
        redirect_to new_signup_path and return
      end
    end

    target = current_household || Household.installation
    return unless target&.onboarded?

    if authenticated?
      redirect_to root_path, alert: "Your family kitchen is already set up."
    else
      redirect_to select_profile_path, alert: "This kitchen is already configured. Please select your profile."
    end
  end

  def load_starter_recipes
    config = YAML.load_file(Rails.root.join("config/starter_recipes.yml"))
    @starter_recipes = config["starter_recipes"] || []
  end

  def household_params
    params.require(:household).permit(:name, :breakfast_time, :lunch_time, :dinner_time)
  end

  def admin_member_params
    params.require(:admin_member).permit(:name, :pin, :avatar_color, :avatar_icon)
  end

  def family_member_params
    allowed = params.require(:family_member).permit(:name, :pin, :avatar_color, :avatar_icon)
    allowed[:role] = params[:family_member][:role] if params.dig(:family_member, :role).in?(%w[admin member])
    allowed
  end
end
