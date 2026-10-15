# The household's shared grocery ticks, for the checklist's JavaScript. Any
# profile may read them; writing is organizer-only, like the checkboxes. Always
# scoped to the signed-in household.
class GroceryTicksController < ApplicationController
  before_action :force_json
  before_action :require_admin, only: %i[update destroy]
  before_action :set_list

  # { ticks: { item_key => checked } } for the list.
  def index
    render json: { ticks: ticks.checked_map }
  end

  # One change: { from, to, item_key, checked, changed_at }. Responds with the
  # state that stands, which is not the one sent if a newer change got there first.
  def update
    changed_at = parse_time(params[:changed_at])
    checked = ActiveModel::Type::Boolean.new.cast(params[:checked]) unless params[:checked].nil?
    return render_invalid("changed_at is not a time") if changed_at.nil?
    return render_invalid("checked is required") if checked.nil?

    tick = GroceryTick.record!(household: current_household, from: @from, to: @to,
                               item_key: params[:item_key].to_s, checked: checked,
                               changed_at: changed_at, family_member: current_family_member)
    render json: { item_key: tick.item_key, checked: tick.checked }
  rescue ActiveRecord::RecordInvalid => e
    render_invalid(e.record.errors.full_messages.to_sentence)
  end

  # Reset: forget every tick on the list, for every device.
  def destroy
    ticks.delete_all
    render json: { ticks: {} }
  end

  private

  def force_json
    request.format = :json
  end

  def ticks
    current_household.grocery_ticks.for_list(@from, @to)
  end

  def set_list
    @from = MealPlanSlot.parse_date(params[:from])
    @to = MealPlanSlot.parse_date(params[:to])
    valid = @from && @to && @to >= @from && (@to - @from).to_i < GroceryRange::MAX_DAYS
    render_invalid("from and to must be dates, at most #{GroceryRange::MAX_DAYS} days apart") unless valid
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def render_invalid(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
