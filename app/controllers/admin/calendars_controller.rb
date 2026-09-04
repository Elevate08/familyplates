module Admin
  class CalendarsController < BaseController
    before_action :set_household

    def show
      redirect_to edit_admin_calendar_path
    end

    def edit
      @service_email = GoogleCalendarService.service_account_email(@household)
    end

    def update
      if @household.update(calendar_params)
        redirect_to edit_admin_calendar_path, notice: "Google Calendar settings saved successfully! 📅"
      else
        @service_email = GoogleCalendarService.service_account_email(@household)
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::Encryption::Errors::Configuration
      # An install upgraded past the release that started encrypting this, but
      # without setting the keys. Say so plainly instead of returning a 500 that
      # names an internal error class.
      redirect_to edit_admin_calendar_path,
        alert: "This server is not set up to store credentials securely yet. " \
               "Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY and " \
               "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT, restart, and try again. " \
               "See the deployment guide."
    end

    def test_connection
      target_id = params[:google_calendar_id].presence || @household.google_calendar_id
      result = GoogleCalendarService.new(@household).test_connection(target_id)

      respond_to do |format|
        format.json { render json: result }
        format.html do
          if result[:success]
            redirect_to edit_admin_calendar_path, notice: "Google Calendar connection verified successfully! 📅 Target: \"#{result[:summary]}\""
          else
            redirect_to edit_admin_calendar_path, alert: "Google Calendar connection failed: #{result[:error]}"
          end
        end
      end
    end

    def sync_plan
      current_plan = @household.current_meal_plan
      service = GoogleCalendarService.new(@household)
      synced_count = service.sync_meal_plan(current_plan)

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            synced_count: synced_count,
            message: "Successfully synced #{synced_count} meal #{'slot'.pluralize(synced_count)} to Google Calendar!"
          }
        end
        format.html { redirect_to edit_admin_calendar_path, notice: "Full meal plan sync to Google Calendar completed! 📅" }
      end
    end

    def regenerate_feed_token
      @household.regenerate_calendar_feed_token
      redirect_to edit_admin_calendar_path, notice: "Calendar subscription feed link has been regenerated! 🔄 Previous subscription links have been revoked."
    end

    private

    def set_household
      @household = current_household
    end

    def calendar_params
      permitted = params.require(:household).permit(
        :google_calendar_id,
        :google_calendar_enabled,
        :google_service_account_json,
        :remove_google_service_account_json
      )

      removing = permitted.delete(:remove_google_service_account_json) == "1"

      # The form cannot show the stored key, so a blank field means "leave it
      # alone" rather than "clear it" - otherwise saving a calendar ID would
      # silently wipe the credential. Removing is an explicit choice.
      if removing
        permitted[:google_service_account_json] = nil
      elsif permitted[:google_service_account_json].blank?
        permitted.delete(:google_service_account_json)
      end

      permitted
    end
  end
end
