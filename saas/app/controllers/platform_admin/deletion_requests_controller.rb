module PlatformAdmin
  class DeletionRequestsController < BaseController
    def index
      @requests = AccountDeletionRequest.includes(:household, :requested_by_user).pending.order(requested_at: :asc)
    end

    def destroy
      request_record = AccountDeletionRequest.includes(:household).find(params[:id])
      household = request_record.household
      unless params[:confirmation].to_s == household.name
        redirect_to platform_admin_deletion_requests_path, alert: "Type the exact household name to permanently delete it." and return
      end

      users = household.users.to_a
      # Cancelled before the household row goes, because destroying it removes
      # the local Pay records that are the only link to the Stripe subscription.
      uncancelled = household.cancel_subscriptions_before_deletion!
      record_platform_audit!(
        "household.permanently_deleted",
        target: household,
        metadata: { request_id: request_record.id, uncancelled_subscriptions: uncancelled.map(&:processor_id) }
      )
      household.destroy!
      users.each do |user|
        user.destroy! if user.reload.households.none?
      rescue ActiveRecord::RecordNotFound
      end
      if uncancelled.any?
        redirect_to platform_admin_deletion_requests_path,
                    alert: "Household permanently deleted, but these Stripe subscriptions could not be cancelled and must be cancelled manually in Stripe: #{uncancelled.map(&:processor_id).join(', ')}."
      else
        redirect_to platform_admin_deletion_requests_path, notice: "Household permanently deleted."
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to platform_admin_deletion_requests_path, alert: "Failed to permanently delete household: #{e.message}"
    end
  end
end
