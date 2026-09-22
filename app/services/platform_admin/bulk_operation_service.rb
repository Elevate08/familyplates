# frozen_string_literal: true

module PlatformAdmin
  class BulkOperationService
    ALLOWED_ACTIONS = %w[add_tag remove_tag assign_promotion extend_trial send_announcement].freeze

    Result = Data.define(:action, :reason, :matched_count, :success_count, :skipped_count, :error_count, :errors, :audit_event)

    attr_reader :operator, :action, :params, :filter_params, :reason

    def initialize(operator:, action:, params: {}, filter_params: {}, reason: nil)
      @operator = operator
      @action = action.to_s.strip
      @params = params.to_h.with_indifferent_access
      @filter_params = filter_params.to_h.with_indifferent_access
      @reason = reason.to_s.strip
    end

    def valid_action?
      ALLOWED_ACTIONS.include?(@action)
    end

    def base_scope
      scope = Household.all

      if (status = filter_params[:status].presence)
        case status
        when "active" then scope = scope.where(suspended_at: nil)
        when "suspended" then scope = scope.where.not(suspended_at: nil)
        when "trialing" then scope = scope.trial_active
        end
      end

      if (promo_filter = filter_params[:promo_filter].presence)
        case promo_filter
        when "with_promo" then scope = scope.where.not(promotion_code: [ nil, "" ])
        when "without_promo" then scope = scope.where(promotion_code: [ nil, "" ])
        end
      end

      if (tag = filter_params[:tag].presence)
        scope = scope.with_operational_tag(tag)
      end

      if (search = filter_params[:search].presence)
        pattern = "%#{search.strip}%"
        scope = scope.left_outer_joins(:users).where(
          "households.name LIKE :p OR households.id LIKE :p OR users.email LIKE :p",
          p: pattern
        ).distinct
      end

      scope
    end

    def preview
      households = base_scope.includes(:pay_subscriptions, :users).to_a
      eligible = []
      ineligible = []

      households.each do |household|
        eligibility = check_eligibility(household)
        if eligibility[:eligible]
          eligible << { household: household, detail: eligibility[:detail] }
        else
          ineligible << { household: household, reason: eligibility[:reason] }
        end
      end

      {
        action: action,
        matched_count: households.size,
        eligible_count: eligible.size,
        ineligible_count: ineligible.size,
        samples: eligible.first(10),
        ineligible_samples: ineligible.first(5),
        details: preview_action_details
      }
    end

    def execute!
      raise ArgumentError, "Reason is mandatory for bulk operations" if reason.blank?
      raise ArgumentError, "Invalid action: #{action}" unless valid_action?

      households = base_scope.includes(:pay_subscriptions, :users).to_a
      success_count = 0
      skipped_count = 0
      errors = []

      ActiveRecord::Base.transaction do
        households.each do |household|
          eligibility = check_eligibility(household)
          unless eligibility[:eligible]
            skipped_count += 1
            next
          end

          begin
            apply_action!(household)
            success_count += 1
          rescue StandardError => e
            errors << { household_id: household.id, error: e.message }
          end
        end

        raise ActiveRecord::Rollback if errors.size > (households.size / 2) && households.size > 2
      end

      audit_event = PlatformAuditEvent.record!(
        action: "bulk_operation.executed",
        actor: operator,
        metadata: {
          bulk_action: action,
          reason: reason,
          matched_count: households.size,
          success_count: success_count,
          skipped_count: skipped_count,
          error_count: errors.size,
          filters: filter_params.slice(:status, :promo_filter, :tag, :search),
          parameters: sanitized_params
        }
      )

      Result.new(
        action: action,
        reason: reason,
        matched_count: households.size,
        success_count: success_count,
        skipped_count: skipped_count,
        error_count: errors.size,
        errors: errors,
        audit_event: audit_event
      )
    end

    private

    def check_eligibility(household)
      case action
      when "add_tag"
        tag = params[:tag].to_s.strip
        return { eligible: false, reason: "No tag specified" } if tag.blank?
        return { eligible: false, reason: "Already has tag '#{tag}'" } if household.has_operational_tag?(tag)
        { eligible: true, detail: "Add tag '#{tag}'" }

      when "remove_tag"
        tag = params[:tag].to_s.strip
        return { eligible: false, reason: "No tag specified" } if tag.blank?
        return { eligible: false, reason: "Does not have tag '#{tag}'" } unless household.has_operational_tag?(tag)
        { eligible: true, detail: "Remove tag '#{tag}'" }

      when "assign_promotion"
        code = params[:promotion_code].to_s.strip.upcase
        prog = PromotionProgram.find_by(code: code)
        return { eligible: false, reason: "Promotion '#{code}' not found" } unless prog
        return { eligible: false, reason: "Promotion '#{code}' is inactive" } unless prog.active?
        return { eligible: false, reason: "Already has promotion '#{code}'" } if household.promotion_code == code
        { eligible: true, detail: "Apply promotion '#{code}' (#{prog.name})" }

      when "extend_trial"
        days = params[:days].to_i
        return { eligible: false, reason: "Days must be greater than 0" } if days <= 0
        return { eligible: false, reason: "Cannot extend trial for active paid subscriber" } if household.active_subscription?
        new_date = (household.trial_ends_at || Time.current) + days.days
        { eligible: true, detail: "Extend trial to #{new_date.to_date}" }

      when "send_announcement"
        subject = params[:subject].to_s.strip
        body = params[:body].to_s.strip
        return { eligible: false, reason: "Subject is required" } if subject.blank?
        return { eligible: false, reason: "Body is required" } if body.blank?
        { eligible: true, detail: "Create support announcement thread '#{subject}'" }

      else
        { eligible: false, reason: "Unknown action" }
      end
    end

    def apply_action!(household)
      case action
      when "add_tag"
        household.add_operational_tag(params[:tag])
        household.save!(validate: false)

      when "remove_tag"
        household.remove_operational_tag(params[:tag])
        household.save!(validate: false)

      when "assign_promotion"
        code = params[:promotion_code].to_s.strip.upcase
        household.update!(promotion_code: code)

      when "extend_trial"
        days = params[:days].to_i
        new_end = (household.trial_ends_at || Time.current) + days.days
        household.update!(trial_extended_until: new_end)

      when "send_announcement"
        thread = household.support_threads.create!(
          subject: params[:subject].to_s.strip,
          status: "waiting_on_customer"
        )
        thread.messages.create!(
          body: params[:body].to_s.strip,
          platform_admin: operator
        )
      end
    end

    def preview_action_details
      case action
      when "add_tag" then "Add tag '#{params[:tag]}' to eligible households"
      when "remove_tag" then "Remove tag '#{params[:tag]}' from eligible households"
      when "assign_promotion" then "Assign promotion code '#{params[:promotion_code]}' to eligible households"
      when "extend_trial" then "Extend trial duration by #{params[:days].to_i} days"
      when "send_announcement" then "Broadcast service announcement: '#{params[:subject]}'"
      else "Execute operation"
      end
    end

    def sanitized_params
      params.except(:password, :token)
    end
  end
end
