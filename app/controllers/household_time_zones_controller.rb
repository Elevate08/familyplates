# Seeds the zone from the browser. The host TZ is the machine, not the family.
# Never overwrites a zone already set. The name is checked against the zone table.
class HouseholdTimeZonesController < ApplicationController
  def create
    current_household.adopt_time_zone(params[:time_zone])

    # The page is already drawn. Re-rendering under a new clock would move the meal plan.
    head :no_content
  end
end
