# frozen_string_literal: true

require "ipaddr"

module FamilyPlates
  class Error < StandardError; end
  class AdminPasswordRequiredError < Error; end
  class OutboundEmailNotConfiguredError < Error; end

  class HostedEditionMissingError < Error; end

  class Config
    # Hosted mode needs the saas/ engine, which only the hosted bundle loads,
    # and the hosted bundle defaults to it. The test suite pins a default of
    # its own (test_helper.rb), so a test runs as an appliance on either
    # bundle unless it asks for hosted.
    attr_writer :default_mode

    def mode=(value)
      FamilyPlates.require_hosted_edition! if value.to_s == "hosted"
      @mode = value
    end

    def mode
      @mode || @default_mode || ENV["FAMILYPLATES_MODE"].presence || ENV["APP_MODE"].presence ||
        (FamilyPlates.saas? ? "hosted" : "appliance")
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
    attr_accessor :oidc_issuer, :oidc_client_id, :oidc_client_secret, :oidc_auth_url, :oidc_token_url, :oidc_userinfo_url, :oidc_jwks_url, :oidc_display_name, :oidc_scope
    attr_accessor :forward_auth_email_headers, :forward_auth_user_headers, :forward_auth_name_headers, :forward_auth_logout_url
    attr_writer :google_auth_enabled, :oidc_auth_enabled, :forward_auth_enabled

    def google_auth_enabled?
      enabled = @google_auth_enabled.nil? ? (ENV["AUTH_GOOGLE_ENABLED"] == "true") : @google_auth_enabled
      enabled && google_client_id.present? && google_client_secret.present?
    end

    def oidc_enabled?
      enabled = @oidc_auth_enabled.nil? ? (ENV["AUTH_OIDC_ENABLED"] == "true") : @oidc_auth_enabled
      # The issuer is required: every id_token is checked against it.
      enabled && oidc_client_id.present? && oidc_client_secret.present? && oidc_issuer.present?
    end

    def forward_auth_enabled?
      if @forward_auth_enabled.nil?
        ENV["AUTH_FORWARD_AUTH_ENABLED"] == "true" || ENV["FORWARD_AUTH_ENABLED"] == "true"
      else
        @forward_auth_enabled
      end
    end

    def any_oauth_enabled?
      google_auth_enabled? || oidc_enabled?
    end

    def google_client_id
      @google_client_id || ENV["GOOGLE_CLIENT_ID"]
    end

    def google_client_secret
      @google_client_secret || ENV["GOOGLE_CLIENT_SECRET"]
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

    # Only for a provider without discovery; otherwise read from discovery.
    def oidc_jwks_url
      @oidc_jwks_url || ENV["OIDC_JWKS_URL"]
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

    def forward_auth_trusted_proxies=(value)
      @forward_auth_proxies = nil
      @forward_auth_trusted_proxies = value
    end

    # The single-host addresses in forward_auth_trusted_proxies, parsed once.
    # A network range would make every client inside it a trusted hop, so range
    # entries (and entries that are not an IP address) are ignored.
    ForwardAuthProxies = Struct.new(:hosts, :ignored)

    def forward_auth_proxies
      @forward_auth_proxies ||= begin
        parsed = forward_auth_trusted_proxies.map(&:strip).compact_blank.map do |entry|
          [ entry, FamilyPlates.native_ip(IPAddr.new(entry)) ]
        rescue IPAddr::Error
          [ entry, nil ]
        end
        hosts, others = parsed.partition { |_, ip| ip && FamilyPlates.host_address?(ip) }
        ignored = others.map { |entry, ip| "#{entry} (#{ip ? 'range' : 'not an IP address'})" }
        ForwardAuthProxies.new(hosts.map(&:last).freeze, ignored.freeze).freeze
      end
    end

    # Called once at boot, so an operator can see why forward-auth sign-in stopped.
    def log_ignored_forward_auth_proxies(logger)
      return unless forward_auth_enabled?

      proxies = forward_auth_proxies
      logger.warn("[auth] FORWARD_AUTH_TRUSTED_PROXIES ignored entries: #{proxies.ignored.join(', ')}") if proxies.ignored.any?
      logger.warn("[auth] FORWARD_AUTH_TRUSTED_PROXIES has no usable address; forward-auth will not sign anyone in") if proxies.hosts.empty?
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
      @oidc_auth_enabled = nil
      @oidc_issuer = nil
      @oidc_client_id = nil
      @oidc_client_secret = nil
      @oidc_auth_url = nil
      @oidc_token_url = nil
      @oidc_userinfo_url = nil
      @oidc_jwks_url = nil
      @oidc_display_name = nil
      @oidc_scope = nil
      @forward_auth_enabled = nil
      @forward_auth_trusted_proxies = nil
      @forward_auth_proxies = nil
      @forward_auth_email_headers = nil
      @forward_auth_user_headers = nil
      @forward_auth_name_headers = nil
      @forward_auth_logout_url = nil
    end
  end

  def self.config
    @config ||= Config.new
  end

  # An IPv4-mapped IPv6 address (or range, such as ::ffff:172.18.0.0/112)
  # becomes the IPv4 one, so it compares equal to the same IPv4 address.
  def self.native_ip(ip)
    return ip unless ip.ipv4_mapped? && ip.prefix >= 96

    ip.native.mask(ip.prefix - 96)
  end

  # A single host address; a value that parses as a range is not one.
  def self.host_address?(ip)
    ip.prefix == (ip.ipv4? ? 32 : 128)
  end

  # True when the hosted edition's engine is loaded (Gemfile.saas).
  def self.saas?
    defined?(FamilyPlatesSaas::Engine) ? true : false
  end

  def self.require_hosted_edition!
    return if saas?

    raise HostedEditionMissingError, "FAMILYPLATES_MODE is hosted, but this is the appliance edition: it does not " \
      "include the saas/ engine. Use the hosted image (docker build --build-arg EDITION=hosted), or run from a " \
      "checkout with Gemfile.saas. To run an appliance, unset FAMILYPLATES_MODE."
  end

  def self.configure
    yield config
  end

  def self.installed?
    if config.hosted?
      true
    else
      Household.installed?
    end
  end

  def self.can_enable_require_login?(household = nil)
    target_household = household || Household.installation
    return false unless target_household

    target_household.can_require_login?
  end

  # The addresses that may sit between a client and the app, for
  # config.action_dispatch.trusted_proxies. Rails' default trusts every private
  # range, so on an appliance (a LAN, or the Docker bridge) any client could name
  # its own address in X-Forwarded-For and dodge the per-IP sign-in and PIN
  # limits. An appliance trusts only loopback (Thruster, in the image) and the
  # single addresses in TRUSTED_PROXIES, so remote_ip is the last hop that is not
  # one of them: the address Thruster, or the operator's proxy, saw.
  #
  # Returns nil for the hosted edition, which keeps Rails' default. Its clients
  # arrive from public addresses, and kamal-proxy reaches the app from a private
  # one: narrowing the list would give every user kamal-proxy's address.
  def self.trusted_proxies(hosted: config.hosted?, extra: ENV["TRUSTED_PROXIES"])
    return if hosted

    loopback = %w[127.0.0.0/8 ::1].map { |address| IPAddr.new(address) }
    loopback + extra.to_s.split(",").map(&:strip).compact_blank.map { |address| single_proxy_address(address) }
  end

  def self.single_proxy_address(address)
    ip = IPAddr.new(address)
    raise IPAddr::Error, "a range" unless ip.to_range.first == ip.to_range.last

    ip
  rescue IPAddr::Error
    raise ArgumentError, "TRUSTED_PROXIES must list single IP addresses, comma-separated; #{address.inspect} is not one."
  end
  private_class_method :single_proxy_address

  # Hostname operators set for a public deploy. Blank on a LAN appliance.
  def self.public_host
    ENV["APP_HOST"].to_s.strip.sub(%r{\Ahttps?://}i, "").split("/").first.presence
  end

  def self.hosted_host_missing?(environment: Rails.env)
    environment.production? && config.hosted? && public_host.blank?
  end

  # Locks the Host header to the public name and uses that name in mail links.
  # /up stays open so a container health check can call the app by its own address.
  def self.apply_public_host!(host = public_host)
    return if host.blank?

    rails_config = Rails.application.config
    rails_config.hosts << host unless rails_config.hosts.include?(host)
    rails_config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
    protocol = (config.hosted? || rails_config.force_ssl) ? "https" : "http"
    rails_config.action_mailer.default_url_options = { host: host, protocol: protocol }
  end

  module OutboundEmail
    SMTP_ENV_KEYS = %w[SMTP_ADDRESS SMTP_USER_NAME SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION].freeze

    def self.validate!(environment: Rails.env)
      return unless environment.production?
      return unless required? || enabled?

      if ENV["SMTP_ADDRESS"].blank?
        raise OutboundEmailNotConfiguredError, smtp_address_message
      end

      username = ENV["SMTP_USER_NAME"].presence || ENV["SMTP_USERNAME"].presence
      if username.present? && ENV["SMTP_PASSWORD"].blank?
        raise OutboundEmailNotConfiguredError, "SMTP_PASSWORD is required when an SMTP username is set."
      end
    end

    def self.required?
      FamilyPlates.config.hosted?
    end

    def self.enabled?
      SMTP_ENV_KEYS.any? { |key| ENV[key].present? }
    end

    def self.smtp_address_message
      if required?
        "Hosted mode sends sign-in codes by email and will not start until SMTP_ADDRESS is set."
      else
        "SMTP settings were provided without SMTP_ADDRESS."
      end
    end
    private_class_method :smtp_address_message
  end
end
