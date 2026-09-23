class PantryItemsController < ApplicationController
  before_action :set_pantry_item, only: %i[update destroy toggle_staple toggle_low mark_low restock]

  def index
    load_pantry_items
    @new_item = current_household.pantry_items.build
  end

  def create
    @pantry_item = current_household.pantry_items.build(pantry_item_params)
    if @pantry_item.save
      track_activity("pantry_item.created", target: @pantry_item)
      redirect_to pantry_items_path, notice: "#{@pantry_item.name} added to pantry."
    else
      render_index_with_errors
    end
  end

  def update
    if @pantry_item.update(pantry_item_params)
      track_activity("pantry_item.updated", target: @pantry_item)
      redirect_to pantry_items_path, notice: "Pantry item updated."
    else
      render_index_with_errors
    end
  end

  def destroy
    track_activity("pantry_item.deleted", target: @pantry_item)
    @pantry_item.destroy
    redirect_to pantry_items_path, notice: "#{@pantry_item.name} removed from pantry."
  end

  def toggle_staple
    @pantry_item.toggle_staple!
    redirect_to pantry_items_path
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
    track_activity("pantry_item.marked_low", target: @pantry_item)

    render_stock_change
  end

  def restock
    @pantry_item.mark_restocked!
    track_activity("pantry_item.restocked", target: @pantry_item)

    render_stock_change
  end

  private

  def load_pantry_items
    @pantry_items = current_household.pantry_items.order(:aisle_category, :name)
    @items_by_category = @pantry_items.group_by(&:aisle_category)
  end

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

  # Turbo asks for turbo-stream and will not fall back to HTML, so :index 500s.
  # Ask for HTML; Turbo renders a 422 without a second template.
  def render_index_with_errors
    load_pantry_items
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
