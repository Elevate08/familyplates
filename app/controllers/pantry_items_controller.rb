class PantryItemsController < ApplicationController
  before_action :set_pantry_item, only: %i[update destroy toggle_staple toggle_low mark_low restock]

  def index
    @pantry_items = current_household.pantry_items.order(:aisle_category, :name)
    @items_by_category = @pantry_items.group_by(&:aisle_category)
    @new_item = current_household.pantry_items.build
  end

  def create
    @pantry_item = current_household.pantry_items.build(pantry_item_params)
    if @pantry_item.save
      track_activity("pantry_item.created", target: @pantry_item)
      respond_to do |format|
        format.turbo_stream { redirect_to pantry_items_path, notice: "#{@pantry_item.name} added to pantry." }
        format.html { redirect_to pantry_items_path, notice: "#{@pantry_item.name} added to pantry." }
      end
    else
      render_index_with_errors
    end
  end

  def update
    if @pantry_item.update(pantry_item_params)
      track_activity("pantry_item.updated", target: @pantry_item)
      respond_to do |format|
        format.turbo_stream { redirect_to pantry_items_path, notice: "Pantry item updated." }
        format.html { redirect_to pantry_items_path, notice: "Pantry item updated." }
      end
    else
      render_index_with_errors
    end
  end

  def destroy
    track_activity("pantry_item.deleted", target: @pantry_item)
    @pantry_item.destroy
    respond_to do |format|
      format.turbo_stream { redirect_to pantry_items_path, notice: "#{@pantry_item.name} removed from pantry." }
      format.html { redirect_to pantry_items_path, notice: "#{@pantry_item.name} removed from pantry." }
    end
  end

  def toggle_staple
    @pantry_item.toggle_staple!
    respond_to do |format|
      format.turbo_stream { redirect_to pantry_items_path }
      format.html { redirect_to pantry_items_path }
    end
  end

  # "Low on this" - one tap, from the pantry roster, a recipe's ingredient list,
  # or the drawer in Cook Mode. Answers in place rather than reloading, because
  # two of those three surfaces are mid-task.
  def toggle_low
    @pantry_item.toggle_low!
    track_activity(@pantry_item.low_stock? ? "pantry_item.marked_low" : "pantry_item.restocked", target: @pantry_item)

    render_stock_change
  end

  # The two idempotent ends, driven by ticking a Restock line on the grocery
  # list - and by un-ticking it, which has to put the flag back.
  def mark_low
    @pantry_item.mark_low!
    render_stock_change
  end

  def restock
    @pantry_item.mark_restocked!
    track_activity("pantry_item.restocked", target: @pantry_item)

    render_stock_change
  end

  private

  # Replaces just the row that changed. A full reload would lose the cook's
  # place in a recipe, and scroll the pantry back to the top.
  def render_stock_change
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          view_context.dom_id(@pantry_item, :stock),
          partial: "pantry_items/stock_toggle",
          locals: { pantry_item: @pantry_item }
        )
      end
      format.html { redirect_back fallback_location: pantry_items_path }
      format.json { render json: { id: @pantry_item.id, low_stock: @pantry_item.low_stock? } }
    end
  end

  # Turbo submits the pantry form with a text/vnd.turbo-stream.html Accept
  # header, and Rails does not fall back to HTML for that format - there is no
  # index.turbo_stream.erb, so rendering :index for it raised MissingTemplate and
  # every invalid submission became a 500. Turbo renders an HTML 422 fine, so ask
  # for HTML explicitly rather than adding a second template to keep in step.
  def render_index_with_errors
    @pantry_items = current_household.pantry_items.order(:aisle_category, :name)
    @items_by_category = @pantry_items.group_by(&:aisle_category)
    # The form is bound to @new_item, which the old error branches never set -
    # so re-rendering index blew up on form_with model: nil even for HTML.
    # Handing it the rejected record is also what puts the errors on screen.
    @new_item = @pantry_item

    render :index, formats: [ :html ], status: :unprocessable_entity
  end

  def set_pantry_item
    @pantry_item = current_household.pantry_items.find(params[:id])
  end

  def pantry_item_params
    params.require(:pantry_item).permit(:name, :aisle_category, :is_staple, :emoji)
  end
end
