# Seeds the household's time zone from the device in front of it.
#
# There is no way to know a household's zone from the server side: the request
# carries no zone, and the host's own TZ describes the machine, not the family -
# on a hosted install it is whatever region the container runs in. The browser
# does know, exactly, as an IANA name, so it is asked once.
#
# Seed only. A household that has already answered is never overwritten here, so
# a phone that travels, or a guest's laptop, cannot quietly move the kitchen -
# changing a zone already set goes through the household settings form, which is
# admin-only. The submitted name is validated against the zone table either way;
# it arrives from a browser and is not trusted on its face.
class HouseholdTimeZonesController < ApplicationController
  def create
    current_household.adopt_time_zone(params[:time_zone])

    # Nothing to render: the page that asked is already drawn, and a zone
    # arriving now applies from the next request. Re-rendering the view under a
    # changed clock would move the meal plan under the reader.
    head :no_content
  end
end
