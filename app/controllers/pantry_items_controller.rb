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
        format.turbo_stream
        format.html { redirect_to pantry_items_path, notice: "#{@pantry_item.name} added to pantry." }
      end
    else
      @pantry_items = current_household.pantry_items.order(:aisle_category, :name)
      @items_by_category = @pantry_items.group_by(&:aisle_category)
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { render :index, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @pantry_item.update(pantry_item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to pantry_items_path, notice: "Pantry item updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { render :index, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @pantry_item.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pantry_items_path, notice: "#{@pantry_item.name} removed from pantry." }
    end
  end

  def toggle_staple
    @pantry_item.toggle_staple!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to pantry_items_path }
    end
  end

  private

  def set_pantry_item
    @pantry_item = current_household.pantry_items.find(params[:id])
  end

  def pantry_item_params
    params.require(:pantry_item).permit(:name, :aisle_category, :is_staple, :emoji)
  end
end
