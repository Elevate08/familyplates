class AccountDeletionRequestsController < ApplicationController
  allow_suspended_access

  # A deletion request ends the household for everyone - an organizer's
  # decision, not a kiosk's or a child's.
  before_action :require_admin

  def create
    current_household.account_deletion_requests.create!(requested_by_user: current_user || current_family_member&.user, requested_at: Time.current)
    redirect_to account_data_path, notice: "Your deletion request was sent to support for review."
  rescue ActiveRecord::RecordInvalid
    redirect_to account_data_path, alert: "There is already an open deletion request for this household."
  end
end
