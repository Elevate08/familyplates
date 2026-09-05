class AccountDataController < ApplicationController
  allow_suspended_access

  def show
    @household = current_household
    @deletion_request = @household.account_deletion_requests.pending.order(requested_at: :desc).first
  end

  def export
    payload = HouseholdExport.call(current_household)
    send_data JSON.pretty_generate(payload), filename: "familyplates-#{current_household.id}-export.json", type: "application/json", disposition: "attachment"
  end

  def request_deletion
    current_household.account_deletion_requests.create!(requested_by_user: current_user || current_family_member&.user, requested_at: Time.current)
    redirect_to account_data_path, notice: "Your deletion request was sent to support for review."
  rescue ActiveRecord::RecordInvalid
    redirect_to account_data_path, alert: "There is already an open deletion request for this household."
  end
end
