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
        format.html { redirect_to meal_plan_path(@meal_plan), notice: "Meal scheduled!" }
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
    @meal_plan = current_household.meal_plans.find(params[:meal_plan_id])
  end

  def slot_params
    params.require(:meal_plan_slot).permit(:date, :meal_type, :recipe_id, :family_member_id, :custom_title, :notes)
  end
end
