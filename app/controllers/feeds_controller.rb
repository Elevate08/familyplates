class FeedsController < ApplicationController
  allow_unauthenticated_access only: [:calendar]

  def calendar
    @household = Household.find_by!(calendar_token: params[:token])
    ical_content = IcalGenerator.call(@household)

    send_data ical_content,
              filename: "#{@household.name.parameterize}-meals.ics",
              type: "text/calendar; charset=utf-8",
              disposition: "inline"
  end
end
