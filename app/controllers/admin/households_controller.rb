module Admin
  class HouseholdsController < BaseController
    before_action :set_household

    def edit
    end

    def update
      if @household.update(household_params)
        redirect_to admin_root_path, notice: "Household settings updated successfully! 🏡"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def regenerate_calendar_token
      @household.regenerate_calendar_token
      redirect_to admin_root_path, notice: "Calendar feed token has been regenerated! 🔄 Please update your calendar app subscriptions."
    end

    private

    def set_household
      @household = current_household
    end

    def household_params
      params.require(:household).permit(:name)
    end
  end
end
