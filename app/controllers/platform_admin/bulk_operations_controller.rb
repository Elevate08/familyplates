# frozen_string_literal: true

module PlatformAdmin
  class BulkOperationsController < BaseController
    before_action :load_promotions, only: %i[new preview create]

    def index
      record_platform_audit!("bulk_operations.indexed")
      @recent_operations = PlatformAuditEvent.where(action: "bulk_operation.executed")
                                             .order(created_at: :desc)
                                             .limit(50)
      @total_operations = PlatformAuditEvent.where(action: "bulk_operation.executed").count
    end

    def new
      @action = params[:bulk_action].presence || "add_tag"
      @filter_params = safe_filter_params
      @operation_params = safe_operation_params
    end

    def preview
      @action = params[:bulk_action].to_s.strip
      @reason = params[:reason].to_s.strip
      @filter_params = safe_filter_params
      @operation_params = safe_operation_params

      if @reason.blank?
        flash.now[:alert] = "A valid operational reason is required for previewing and executing bulk operations."
        render :new, status: :unprocessable_entity and return
      end

      service = BulkOperationService.new(
        operator: current_platform_admin,
        action: @action,
        params: @operation_params,
        filter_params: @filter_params,
        reason: @reason
      )

      unless service.valid_action?
        flash.now[:alert] = "Invalid bulk operation action selected."
        render :new, status: :unprocessable_entity and return
      end

      @preview = service.preview
    end

    def create
      @action = params[:bulk_action].to_s.strip
      @reason = params[:reason].to_s.strip
      @filter_params = safe_filter_params
      @operation_params = safe_operation_params

      unless params[:confirmed] == "1"
        redirect_to new_platform_admin_bulk_operation_path, alert: "Bulk operation was not confirmed. Please preview and check the confirmation box." and return
      end

      service = BulkOperationService.new(
        operator: current_platform_admin,
        action: @action,
        params: @operation_params,
        filter_params: @filter_params,
        reason: @reason
      )

      begin
        result = service.execute!
        notice_msg = "Bulk operation executed successfully: #{result.success_count} households updated"
        notice_msg += ", #{result.skipped_count} skipped" if result.skipped_count > 0
        notice_msg += ", #{result.error_count} failed" if result.error_count > 0
        redirect_to platform_admin_bulk_operations_path, notice: notice_msg
      rescue ArgumentError => e
        redirect_to new_platform_admin_bulk_operation_path, alert: "Operation aborted: #{e.message}"
      rescue StandardError => e
        redirect_to new_platform_admin_bulk_operation_path, alert: "Failed to execute bulk operation: #{e.message}"
      end
    end

    private

    def safe_filter_params
      if params[:filter_params].is_a?(ActionController::Parameters)
        params.require(:filter_params).permit(:status, :promo_filter, :tag, :search).to_h
      else
        {}
      end
    end

    def safe_operation_params
      if params[:operation_params].is_a?(ActionController::Parameters)
        params.require(:operation_params).permit(:tag, :promotion_code, :days, :subject, :body).to_h
      else
        {}
      end
    end

    def load_promotions
      @available_promotions = PromotionProgram.where(active: true).order(:name)
    end
  end
end
