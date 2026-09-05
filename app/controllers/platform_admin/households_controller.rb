module PlatformAdmin
  class HouseholdsController < BaseController
    PAGE_SIZE = 100

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
      @household = Household.includes(:family_members, :users, :pay_subscriptions, :pay_customers).find(params[:id])
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
      @household = Household.find(params[:id])
      @household.update!(suspended_at: Time.current, suspension_reason: params[:reason].to_s.strip.presence)
      record_platform_audit!("household.suspended", target: @household, metadata: { reason: @household.suspension_reason })
      redirect_to platform_admin_household_path(@household), notice: "Household suspended."
    end

    def restore
      @household = Household.find(params[:id])
      @household.update!(suspended_at: nil, suspension_reason: nil)
      record_platform_audit!("household.restored", target: @household)
      redirect_to platform_admin_household_path(@household), notice: "Household restored."
    end

    private

    def filtered_households
      return Household.all if @search.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"
      Household.left_joins(family_members: :user)
        .where("households.name LIKE :pattern OR users.email LIKE :pattern OR family_members.name LIKE :pattern OR households.promotion_code LIKE :pattern OR households.join_code LIKE :pattern", pattern: pattern)
        .distinct
    end
  end
end
