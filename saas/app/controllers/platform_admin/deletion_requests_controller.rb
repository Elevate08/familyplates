module PlatformAdmin
  class DeletionRequestsController < BaseController
    def index
      @requests = AccountDeletionRequest.includes(:household, :requested_by_user).pending.order(requested_at: :asc)
    end

    # Permanent deletion is irreversible, so support and billing operators are
    # refused; only owner and privacy may erase a household.
    DELETING_ROLES = %w[owner privacy].freeze

    def destroy
      unless current_platform_admin.role.in?(DELETING_ROLES)
        redirect_to platform_admin_deletion_requests_path, alert: "Only an owner or privacy operator can permanently delete a household." and return
      end

      # pending only: a canceled or completed request is no authority to delete.
      request_record = AccountDeletionRequest.includes(:household).pending.find(params[:id])
      household = request_record.household
      unless params[:confirmation].to_s == household.name
        redirect_to platform_admin_deletion_requests_path, alert: "Type the exact household name to permanently delete it." and return
      end

      # Cancelled before the household row goes, because destroying it removes
      # the local Pay records that are the only link to the Stripe subscription.
      # Any failure keeps the household, so the operator can retry.
      failures = household.cancel_subscriptions_before_deletion!
      if failures.any?
        record_cancellation_failure!(request_record, household, failures)
        redirect_to platform_admin_deletion_requests_path, alert: cancellation_failure_alert(failures) and return
      end

      users = household.users.to_a
      request_id = request_record.id
      # Audit and destroy commit together: a failed audit keeps the household and
      # its pending request. Residual: Stripe cancellation above already ran and
      # is not rolled back; a retry skips subscriptions that are already cancelled.
      ActiveRecord::Base.transaction do
        record_platform_audit!("household.permanently_deleted", target: household, metadata: { request_id: request_id })
        household.destroy!
        users.each do |user|
          user.destroy! if user.reload.households.none?
        rescue ActiveRecord::RecordNotFound
        end
      end
      redirect_to platform_admin_deletion_requests_path, notice: "Household permanently deleted."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to platform_admin_deletion_requests_path, alert: "Failed to permanently delete household: #{e.message}"
    end

    private

    def record_cancellation_failure!(request_record, household, failures)
      record_platform_audit!(
        "household.deletion_blocked_by_billing",
        target: household,
        metadata: {
          request_id: request_record.id,
          failed_subscriptions: failures.map do |failure|
            { id: failure.subscription.id, processor_id: failure.subscription.processor_id,
              error: "#{failure.error.class}: #{failure.error.message}".truncate(500) }
          end
        }
      )
    end

    def cancellation_failure_alert(failures)
      ids = failures.map { |failure| failure.subscription.processor_id }.join(", ")
      "Household not deleted: Stripe did not cancel #{ids}. The household, its billing records and this request were kept. " \
        "Any subscription that did cancel stays cancelled and is skipped next time. Check #{failures.one? ? 'it' : 'them'} in Stripe, " \
        "then confirm the deletion again to retry. If you cancel one in the Stripe Dashboard, wait for its webhook to sync first."
    end
  end
end
