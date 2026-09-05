module Admin
  class CalendarsController < BaseController
    before_action :set_household

    def show
      redirect_to edit_admin_calendar_path
    end

    def edit
    end

    def regenerate_feed_token
      @household.regenerate_calendar_feed_token
      redirect_to edit_admin_calendar_path, notice: "Calendar subscription feed link has been regenerated! 🔄 Previous subscription links have been revoked."
    end

    private

    def set_household
      @household = current_household
    end
  end
end
