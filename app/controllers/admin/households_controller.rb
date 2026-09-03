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

    private

    def set_household
      @household = current_household
    end

    def household_params
      params.require(:household).permit(
        :name,
        :google_calendar_id,
        :google_calendar_enabled,
        :google_service_account_json,
        :breakfast_time,
        :lunch_time,
        :dinner_time
      )
    end
  end
end
