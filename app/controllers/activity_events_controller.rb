class ActivityEventsController < ApplicationController
  def index
    @activity_events = current_household.activity_events
      .includes(:actor)
      .order(created_at: :desc, id: :desc)
      .limit(100)
  end
end
