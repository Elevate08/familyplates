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

    def reset_join_code
      @household.reset_join_code!
      redirect_to edit_admin_household_path, notice: "Join code has been reset: #{@household.join_code}"
    end

    private

    def set_household
      @household = current_household
    end

    def household_params
      params.require(:household).permit(
        :name,
        :breakfast_time,
        :lunch_time,
        :dinner_time
      )
    end
  end
end
