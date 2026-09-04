class CalendarFeedsController < ApplicationController
  allow_browser versions: :all
  allow_unauthenticated_access
  skip_before_action :handle_revoked_session
  skip_before_action :set_current_family_member

  before_action :set_household

  def show
    render_feed
  end

  def member
    @member = @household.family_members.find_by(id: params[:member_id])
    if @member.nil?
      head :not_found
      return
    end

    render_feed(member: @member)
  end

  private

  def set_household
    @household = Household.find_by(calendar_feed_token: params[:token])
    head :not_found unless @household
  end

  def render_feed(member: nil)
    last_modified = [
      @household.meal_plan_slots.maximum(:updated_at),
      @household.updated_at
    ].compact.max || @household.created_at

    etag = [
      @household.id,
      @household.calendar_feed_token,
      member&.id,
      last_modified.to_i
    ]

    if stale?(etag: etag, last_modified: last_modified, public: true)
      service = CalendarFeedService.new(
        @household,
        member: member,
        base_url: request.base_url
      )

      filename = if member
                   "familyplates-#{member.name.parameterize}-cooking.ics"
      else
                   "familyplates-#{@household.name.parameterize}.ics"
      end

      send_data service.generate_ics,
                type: "text/calendar; charset=utf-8",
                disposition: "inline",
                filename: filename
    end
  end
end
