class MealPlanSlotsController < ApplicationController
  before_action :set_meal_plan

  def create
    @slot = @meal_plan.meal_plan_slots.find_or_initialize_by(
      date: slot_params[:date],
      meal_type: slot_params[:meal_type] || "dinner"
    )
    @slot.assign_attributes(slot_params)

    if @slot.save
      respond_to do |format|
        format.turbo_stream
        format.html do
          if params[:return_to] == "recipe" && @slot.recipe.present?
            redirect_to @slot.recipe, notice: "Scheduled \"#{@slot.recipe.title}\" for #{@slot.date.strftime('%A, %b %-d')} (#{@slot.meal_type.capitalize})!"
          else
            redirect_to meal_plan_path(@meal_plan), notice: "Meal scheduled!"
          end
        end
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { redirect_to meal_plan_path(@meal_plan), alert: @slot.errors.full_messages.to_sentence }
      end
    end
  end

  def update
    @slot = @meal_plan.meal_plan_slots.find(params[:id])
    if @slot.update(slot_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to meal_plan_path(@meal_plan), notice: "Slot updated." }
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
    @slot.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to meal_plan_path(@meal_plan), notice: "Meal removed from slot." }
    end
  end

  private

  def set_meal_plan
    if params[:meal_plan_id].present?
      @meal_plan = current_household.meal_plans.find(params[:meal_plan_id])
    elsif params[:meal_plan_slot] && params[:meal_plan_slot][:date].present?
      date = Date.parse(params[:meal_plan_slot][:date].to_s) rescue Date.current
      @meal_plan = current_household.meal_plans.find_or_create_by!(week_start_date: date.beginning_of_week)
    else
      @meal_plan = current_household.current_meal_plan
    end
  end

  def slot_params
    params.require(:meal_plan_slot).permit(:date, :meal_type, :recipe_id, :family_member_id, :custom_title, :notes)
  end
end
