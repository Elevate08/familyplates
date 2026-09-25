class AccountDataController < ApplicationController
  allow_suspended_access

  # Export carries every member's email - an organizer's decision, not a
  # kiosk's or a child's.
  before_action :require_admin

  def show
  end

  def export
    payload = HouseholdExport.call(current_household)
    send_data JSON.pretty_generate(payload), filename: "familyplates-#{current_household.id}-export.json", type: "application/json", disposition: "attachment"
  end
end
