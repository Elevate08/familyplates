# Suspension and billing checks for every household page. Fills in the hooks
# the core Authentication concern leaves empty.
module HostedAccess
  extend ActiveSupport::Concern

  private

  def handle_suspended_household
    return unless current_household&.suspended?

    redirect_to suspended_path
  end

  def ensure_household_entitled!
    return unless FamilyPlates.config.hosted?
    return if current_household.nil?
    return if current_household.entitled?

    if current_family_member&.admin?
      redirect_to subscription_path, alert: "Your trial has expired. Please select a subscription to continue using your kitchen." and return
    else
      redirect_to select_profile_path, alert: "Your family's subscription is inactive. Please ask a household organizer to reactivate." and return
    end
  end
end
