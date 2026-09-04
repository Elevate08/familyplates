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

    attr_accessor :google_client_id, :google_client_secret
    attr_accessor :apple_client_id, :apple_team_id, :apple_key_id, :apple_private_key, :apple_client_secret
    attr_accessor :oidc_issuer, :oidc_client_id, :oidc_client_secret, :oidc_auth_url, :oidc_token_url, :oidc_userinfo_url, :oidc_display_name, :oidc_scope
    attr_accessor :forward_auth_trusted_proxies, :forward_auth_email_headers, :forward_auth_user_headers, :forward_auth_name_headers, :forward_auth_logout_url
    attr_writer :google_auth_enabled, :apple_auth_enabled, :oidc_auth_enabled, :forward_auth_enabled

    def google_auth_enabled?
      enabled = @google_auth_enabled.nil? ? (ENV["AUTH_GOOGLE_ENABLED"] == "true") : @google_auth_enabled
      enabled && google_client_id.present? && google_client_secret.present?
    end

    def apple_auth_enabled?
      enabled = @apple_auth_enabled.nil? ? (ENV["AUTH_APPLE_ENABLED"] == "true") : @apple_auth_enabled
      enabled && apple_client_id.present? && (apple_client_secret.present? || (apple_private_key.present? && apple_key_id.present? && apple_team_id.present?))
    end

    def oidc_enabled?
      enabled = @oidc_auth_enabled.nil? ? (ENV["AUTH_OIDC_ENABLED"] == "true") : @oidc_auth_enabled
      enabled && oidc_client_id.present? && oidc_client_secret.present? && (oidc_issuer.present? || (oidc_auth_url.present? && oidc_token_url.present?))
    end

    def forward_auth_enabled?
      if @forward_auth_enabled.nil?
        ENV["AUTH_FORWARD_AUTH_ENABLED"] == "true" || ENV["FORWARD_AUTH_ENABLED"] == "true"
      else
        @forward_auth_enabled
      end
    end

    def any_oauth_enabled?
      google_auth_enabled? || apple_auth_enabled? || oidc_enabled?
    end

    def google_client_id
      @google_client_id || ENV["GOOGLE_CLIENT_ID"]
    end

    def google_client_secret
      @google_client_secret || ENV["GOOGLE_CLIENT_SECRET"]
    end

    def apple_client_id
      @apple_client_id || ENV["APPLE_CLIENT_ID"]
    end

    def apple_team_id
      @apple_team_id || ENV["APPLE_TEAM_ID"]
    end

    def apple_key_id
      @apple_key_id || ENV["APPLE_KEY_ID"]
    end

    def apple_private_key
      @apple_private_key || ENV["APPLE_PRIVATE_KEY"]
    end

    def apple_client_secret
      @apple_client_secret || ENV["APPLE_CLIENT_SECRET"]
    end

    def oidc_issuer
      @oidc_issuer || ENV["OIDC_ISSUER"]
    end

    def oidc_client_id
      @oidc_client_id || ENV["OIDC_CLIENT_ID"]
    end

    def oidc_client_secret
      @oidc_client_secret || ENV["OIDC_CLIENT_SECRET"]
    end

    def oidc_auth_url
      @oidc_auth_url || ENV["OIDC_AUTH_URL"]
    end

    def oidc_token_url
      @oidc_token_url || ENV["OIDC_TOKEN_URL"]
    end

    def oidc_userinfo_url
      @oidc_userinfo_url || ENV["OIDC_USERINFO_URL"]
    end

    def oidc_display_name
      @oidc_display_name || ENV["OIDC_DISPLAY_NAME"].presence || "Single Sign-On"
    end

    def oidc_scope
      @oidc_scope || ENV["OIDC_SCOPE"].presence || "openid profile email"
    end

    def forward_auth_trusted_proxies
      @forward_auth_trusted_proxies || (ENV["FORWARD_AUTH_TRUSTED_PROXIES"].presence || "127.0.0.1,::1").split(",").map(&:strip)
    end

    def forward_auth_email_headers
      @forward_auth_email_headers || (ENV["FORWARD_AUTH_EMAIL_HEADERS"].presence || ENV["FORWARD_AUTH_EMAIL_HEADER"].presence || "Remote-Email,X-Forwarded-Email,Tailscale-User-Login").split(",").map(&:strip)
    end

    def forward_auth_user_headers
      @forward_auth_user_headers || (ENV["FORWARD_AUTH_USER_HEADERS"].presence || ENV["FORWARD_AUTH_USER_HEADER"].presence || "Remote-User,X-Forwarded-User").split(",").map(&:strip)
    end

    def forward_auth_name_headers
      @forward_auth_name_headers || (ENV["FORWARD_AUTH_NAME_HEADERS"].presence || ENV["FORWARD_AUTH_NAME_HEADER"].presence || "Remote-Name,X-Forwarded-Name,X-Forwarded-Preferred-Username").split(",").map(&:strip)
    end

    def forward_auth_logout_url
      @forward_auth_logout_url || ENV["FORWARD_AUTH_LOGOUT_URL"]
    end

    def reset!
      @mode = nil
      @require_login = nil
      @google_auth_enabled = nil
      @google_client_id = nil
      @google_client_secret = nil
      @apple_auth_enabled = nil
      @apple_client_id = nil
      @apple_team_id = nil
      @apple_key_id = nil
      @apple_private_key = nil
      @apple_client_secret = nil
      @oidc_auth_enabled = nil
      @oidc_issuer = nil
      @oidc_client_id = nil
      @oidc_client_secret = nil
      @oidc_auth_url = nil
      @oidc_token_url = nil
      @oidc_userinfo_url = nil
      @oidc_display_name = nil
      @oidc_scope = nil
      @forward_auth_enabled = nil
      @forward_auth_trusted_proxies = nil
      @forward_auth_email_headers = nil
      @forward_auth_user_headers = nil
      @forward_auth_name_headers = nil
      @forward_auth_logout_url = nil
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
