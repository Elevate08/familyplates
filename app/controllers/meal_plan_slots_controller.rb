class MealPlanSlotsController < ApplicationController
  before_action :set_meal_plan
  before_action :require_admin, only: %i[create update destroy]

  def create
    @slot = @meal_plan.meal_plan_slots.find_or_initialize_by(
      date: slot_params[:date],
      meal_type: slot_params[:meal_type] || "dinner"
    )
    @slot.assign_attributes(slot_params)

    if @slot.save
      track_activity(
        "meal_plan_slot.created",
        target: @slot,
        metadata: { target_name: @slot.recipe&.title || @slot.custom_title || @slot.date.to_s }
      )
      RecipeRequest.auto_fulfill_passed_slots!(current_household)
      respond_to do |format|
        if params[:return_to] == "recipe" && @slot.recipe.present?
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace("recipe_schedule_feedback", partial: "recipes/schedule_feedback", locals: { notice: "📅 Scheduled for #{@slot.date.strftime('%A, %b %-d')} (#{@slot.meal_type.capitalize})!" }),
              turbo_stream.replace("recipe_#{@slot.recipe.id}_heart", partial: "recipe_requests/heart_button", locals: { recipe: @slot.recipe.reload }),
              turbo_stream.replace("recipe_#{@slot.recipe.id}_show_craving", partial: "recipe_requests/show_widget", locals: { recipe: @slot.recipe.reload })
            ]
          end
          format.html do
            redirect_to @slot.recipe, notice: "📅 Scheduled \"#{@slot.recipe.title}\" for #{@slot.date.strftime('%A, %b %-d')} (#{@slot.meal_type.capitalize})!", status: :see_other
          end
        else
          format.turbo_stream
          format.html do
            redirect_to meal_plan_path(@meal_plan), notice: "Meal scheduled!"
          end
        end
      end
    else
      respond_to do |format|
        if params[:return_to] == "recipe"
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("recipe_schedule_feedback", partial: "recipes/schedule_feedback", locals: { alert: @slot.errors.full_messages.to_sentence })
          end
          format.html { redirect_to recipe_path(slot_params[:recipe_id]), alert: @slot.errors.full_messages.to_sentence }
        else
          format.turbo_stream { render :create, status: :unprocessable_entity }
          format.html { redirect_to meal_plan_path(@meal_plan), alert: @slot.errors.full_messages.to_sentence }
        end
      end
    end
  rescue ActiveRecord::InvalidForeignKey
    @slot.errors.add(:base, "That recipe, cook, or leftover meal no longer exists.")
    respond_to do |format|
      format.turbo_stream { render :create, status: :unprocessable_entity }
      format.html { redirect_to meal_plan_path(@meal_plan), alert: @slot.errors.full_messages.to_sentence }
    end
  end

  def update
    # Household has_many :meal_plan_slots, through: :meal_plans, so this is one
    # query scoped to the household. The chain it replaces ran a join, took the
    # first plan, searched it, and fell back to @meal_plan - which quietly
    # widened the scope to any slot in the current plan if the first lookup
    # missed.
    @slot = current_household.meal_plan_slots.find(params[:id])

    @old_date = @slot.date
    @old_meal_type = @slot.meal_type

    if @slot.move(slot_params, household: current_household)
      track_activity(
        "meal_plan_slot.updated",
        target: @slot,
        metadata: { target_name: @slot.recipe&.title || @slot.custom_title || @slot.date.to_s }
      )
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to meal_plan_path(@meal_plan), notice: "Planned meal updated successfully!" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { redirect_to meal_plan_path(@meal_plan), alert: @slot.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @slot = @meal_plan.meal_plan_slots.find(params[:id])
    @date = @slot.date
    @meal_type = @slot.meal_type
    track_activity(
      "meal_plan_slot.deleted",
      target: @slot,
      metadata: { target_name: @slot.recipe&.title || @slot.custom_title || @slot.date.to_s }
    )
    @slot.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to meal_plan_path(@meal_plan), notice: "Meal removed from slot." }
    end
  end

  private

  def set_meal_plan
    if params[:meal_plan_id].present?
      @meal_plan = current_household.meal_plans.find_by(number: params[:meal_plan_id]) || current_household.meal_plans.find_by(id: params[:meal_plan_id])
      raise ActiveRecord::RecordNotFound, "Couldn't find MealPlan with 'id'=#{params[:meal_plan_id]}" unless @meal_plan
    elsif params[:meal_plan_slot] && params[:meal_plan_slot][:date].present?
      date = Date.parse(params[:meal_plan_slot][:date].to_s) rescue household_today
      @meal_plan = current_household.meal_plans.find_or_create_by!(week_start_date: date.beginning_of_week)
    else
      @meal_plan = current_household.current_meal_plan
    end
  end

  def slot_params
    params.require(:meal_plan_slot).permit(:date, :meal_type, :scheduled_time, :recipe_id, :family_member_id, :custom_title, :notes, :is_leftover, :leftover_source_slot_id)
  end
end
