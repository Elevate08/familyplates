# frozen_string_literal: true

module FamilyPlates
  class Error < StandardError; end
  class AdminPasswordRequiredError < Error; end
  class OutboundEmailNotConfiguredError < Error; end

  class Config
    attr_writer :mode

    def mode
      @mode || ENV["FAMILYPLATES_MODE"].presence || ENV["APP_MODE"].presence || "appliance"
    end

    def appliance?
      mode == "appliance"
    end

    def hosted?
      mode == "hosted"
    end

    def require_login
      if @require_login.nil?
        ENV["REQUIRE_LOGIN"] == "true" || ENV["REQUIRE_LOGIN"] == "1"
      else
        @require_login
      end
    end

    def require_login=(value)
      boolean_value = ActiveModel::Type::Boolean.new.cast(value)
      if boolean_value && !FamilyPlates.can_enable_require_login?
        raise AdminPasswordRequiredError, "Cannot enable REQUIRE_LOGIN without at least one linked admin profile with a password."
      end

      @require_login = boolean_value
    end

    def reset!
      @mode = nil
      @require_login = nil
    end
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield config
  end

  def self.can_enable_require_login?(household = nil)
    target_household = household || Household.installation
    return false unless target_household

    target_household.can_require_login?
  end

  module OutboundEmail
    def self.validate!(environment: Rails.env)
      return unless FamilyPlates.config.hosted?
      return if environment.test?

      delivery_method = ActionMailer::Base.delivery_method
      if delivery_method.nil?
        raise OutboundEmailNotConfiguredError, "Outbound email is not configured. Hosted mode requires a delivery method."
      elsif delivery_method == :smtp
        smtp = ActionMailer::Base.smtp_settings || {}
        if smtp[:address].blank?
          raise OutboundEmailNotConfiguredError, "Outbound email is not configured. Hosted mode requires SMTP settings."
        end
      end
    end
  end
end
