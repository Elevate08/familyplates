class PantryItemsController < ApplicationController
  before_action :set_pantry_item, only: %i[update destroy toggle_staple]

  def index
    @pantry_items = current_household.pantry_items.order(:aisle_category, :name)
    @items_by_category = @pantry_items.group_by(&:aisle_category)
    @new_item = current_household.pantry_items.build
  end

  def create
    @pantry_item = current_household.pantry_items.build(pantry_item_params)
    if @pantry_item.save
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
      respond_to do |format|
        format.turbo_stream { redirect_to pantry_items_path, notice: "Pantry item updated." }
        format.html { redirect_to pantry_items_path, notice: "Pantry item updated." }
      end
    else
      render_index_with_errors
    end
  end

  def destroy
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

  private

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
