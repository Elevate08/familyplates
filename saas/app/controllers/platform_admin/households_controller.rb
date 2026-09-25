module PlatformAdmin
  class HouseholdsController < BaseController
    PAGE_SIZE = 100

    BILLING_ACTIONS = %i[cancel_subscription refund_charge comp].freeze

    before_action :set_household, only: %i[show suspend restore] + BILLING_ACTIONS
    before_action :require_billing_role!, :require_billing_reason!, only: BILLING_ACTIONS

    rescue_from PlatformAdmin::HouseholdBilling::Error do |error|
      redirect_to platform_admin_household_path(@household), alert: error.message
    end

    def index
      @search = params[:search].to_s.strip
      @status = params[:status].presence_in(%w[active suspended])
      record_platform_audit!("households.indexed", metadata: { search: @search.presence, status: @status })

      @total_count = Household.count
      @suspended_count = Household.where.not(suspended_at: nil).count
      @with_promo_count = Household.where.not(promotion_code: [ nil, "" ]).count

      scope = filtered_households
      scope = if @status == "suspended"
        scope.where.not(suspended_at: nil)
      elsif @status == "active"
        scope.where(suspended_at: nil)
      else
        scope
      end

      @households = scope
        .includes(:family_members, :users, :pay_subscriptions, :pay_customers)
        .order(created_at: :desc, id: :desc)
        .limit(PAGE_SIZE)
    end

    def show
      record_platform_audit!("household.viewed", target: @household)
      @family_members = @household.family_members.order(:created_at, :id)
      @recipes_count = @household.recipes.count
      @meal_plans_count = @household.meal_plans.count
      @pantry_items_count = @household.pantry_items.count
      @last_activity_at = @household.activity_events.maximum(:created_at)
      @recent_activity = @household.activity_events.includes(:actor).order(created_at: :desc, id: :desc).limit(20)
      @subscription_status = @household.subscription_status
      @subscription_plan = @household.subscription_plan_name
      @subscription_expires_at = @household.subscription_expires_at
      @subscription_billing_label = @household.subscription_billing_label
      @applied_promotion_code = @household.applied_promotion_code
      @charges = @household.pay_charges.order(created_at: :desc).limit(20)
    end

    def suspend
      @household.update!(suspended_at: Time.current, suspension_reason: params[:reason].to_s.strip.presence)
      record_platform_audit!("household.suspended", target: @household, metadata: { reason: @household.suspension_reason })
      redirect_to platform_admin_household_path(@household), notice: "Household suspended."
    end

    def restore
      @household.update!(suspended_at: nil, suspension_reason: nil)
      record_platform_audit!("household.restored", target: @household)
      redirect_to platform_admin_household_path(@household), notice: "Household restored."
    end

    def cancel_subscription
      immediately = params[:when] == "now"
      sub = billing.cancel_subscription!(immediately: immediately)
      record_billing_audit!("household.subscription_canceled", subscription_id: sub.processor_id, immediately: immediately)
      notice = immediately ? "Subscription canceled; access has ended." : "Subscription will end on #{sub.ends_at.to_date.to_formatted_s(:long)}."
      redirect_to platform_admin_household_path(@household), notice: notice
    end

    def refund_charge
      refunded = billing.refund_charge!(params[:charge_id], amount_cents: refund_amount_cents)
      record_billing_audit!("household.charge_refunded", charge_id: params[:charge_id], amount_cents: refunded)
      redirect_to platform_admin_household_path(@household), notice: "Refunded #{helpers.number_to_currency(refunded / 100.0)}."
    end

    def comp
      months = Integer(params[:months].to_s, exception: false)
      comped = billing.comp!(months)
      record_billing_audit!("household.comped", months: months, applied_to: comped)
      notice = if comped == :trial
        "Free trial extended to #{@household.reload.trial_ends_at.to_date.to_formatted_s(:long)}."
      else
        "#{months} free #{"month".pluralize(months)} applied; the next charge is on #{@household.reload.payment_processor.subscription.trial_ends_at.to_date.to_formatted_s(:long)}."
      end
      redirect_to platform_admin_household_path(@household), notice: notice
    end

    private

    def billing
      PlatformAdmin::HouseholdBilling.new(@household)
    end

    # Blank means refund everything still refundable.
    def refund_amount_cents
      return if params[:amount].blank?

      (BigDecimal(params[:amount].to_s.delete("$, ")) * 100).round.to_i
    rescue ArgumentError
      raise PlatformAdmin::HouseholdBilling::Error, "Enter the refund as a dollar amount, like 4.00."
    end

    def require_billing_role!
      return if current_platform_admin.can_manage_billing?

      redirect_to platform_admin_household_path(@household), alert: "Only owner and billing operators can change a household's billing."
    end

    def require_billing_reason!
      return if params[:reason].to_s.strip.present?

      redirect_to platform_admin_household_path(@household), alert: "Give a reason; it goes in the audit log."
    end

    def record_billing_audit!(action, **metadata)
      record_platform_audit!(action, target: @household, metadata: metadata.merge(reason: params[:reason].to_s.strip))
    end

    def set_household
      @household = Household.includes(:family_members, :users, :pay_subscriptions, :pay_customers).find(params[:id])
    end

    def filtered_households
      return Household.all if @search.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"
      Household.left_joins(family_members: :user)
        .where("households.name LIKE :pattern ESCAPE '\\' OR users.email LIKE :pattern ESCAPE '\\' OR family_members.name LIKE :pattern ESCAPE '\\' OR households.promotion_code LIKE :pattern ESCAPE '\\' OR households.join_code LIKE :pattern ESCAPE '\\'", pattern: pattern)
        .distinct
    end
  end
end
