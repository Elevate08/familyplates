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
      record_platform_audit!("household.permanently_deleted", target: household, metadata: { request_id: request_record.id })
      household.destroy!
      users.each do |user|
        user.destroy! if user.reload.households.none?
      rescue ActiveRecord::RecordNotFound
        # User already cleaned up
      end
      redirect_to platform_admin_deletion_requests_path, notice: "Household permanently deleted."
    rescue ActiveRecord::RecordNotDestroyed => e
      redirect_to platform_admin_deletion_requests_path, alert: "Failed to permanently delete household: #{e.message}"
    end
  end
end
