module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_installation
    before_action :set_current_user
    before_action :handle_revoked_session
    before_action :set_current_family_member
    before_action :require_authentication
    before_action :handle_suspended_household
    before_action :require_active_family_member
    before_action :ensure_household_entitled!
    helper_method :authenticated?, :current_household, :current_family_member, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_active_family_member, **options
      skip_before_action :ensure_household_entitled!, **options, raise: false
    end

    # For the setup wizard, the only thing that runs before a household exists.
    # Declared per action rather than matched on controller path, because a path
    # prefix cannot say "these two actions but not the other eight".
    def allow_unconfigured_access(**options)
      skip_before_action :require_installation, **options
    end

    def allow_suspended_access(**options)
      skip_before_action :handle_suspended_household, **options
      skip_before_action :require_active_family_member, **options
      skip_before_action :ensure_household_entitled!, **options, raise: false
    end
  end

  private

  def authenticated?
    Current.family_member.present?
  end

  # Nil until sign-in. Do not fall back to Household.installation: an anonymous
  # request must not see a real household. That fallback becomes a cross-tenant leak.
  def current_household
    Current.household
  end

  def current_family_member
    Current.family_member
  end

  def current_user
    Current.user
  end

  def set_current_user
    if forward_auth_active?
      authenticate_via_forward_auth
      return if Current.user.present?
    end

    token = cookies.signed[:session_token]
    return if token.blank?

    session_record = Session.find_by_token(token)
    if session_record && !session_record.expired?
      session_record.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
      Current.session = session_record
      Current.user = session_record.user
      if cookies.signed[:device_kind] != session_record.kind
        write_permanent_signed_cookie(:device_kind, session_record.kind)
      end
    else
      was_kiosk = (session_record&.kiosk? || cookies.signed[:device_kind] == "kiosk")
      session_record&.destroy
      cookies.delete(:session_token)
      cookies.delete(:active_family_member_id)
      cookies.delete(:device_kind)
      Current.session = nil
      Current.user = nil
      Current.family_member = nil
      Current.household = nil
      @session_revoked = true
      @revoked_kiosk = was_kiosk
    end
  end

  def handle_revoked_session
    return unless @session_revoked

    target_path = signed_out_path(kind: @revoked_kiosk ? "kiosk" : "browser")
    message = @revoked_kiosk ? "This kitchen display's access has been revoked." : "Device access has been revoked."

    return if request.path.in?([ signed_out_path, new_pair_path, "/kiosk", new_session_path, token_pair_path, device_authorization_pair_path ])

    if request.format.json?
      render json: { error: "session_revoked", message: message, redirect_url: target_path }, status: :unauthorized and return
    else
      redirect_to target_path, alert: message, status: :see_other and return
    end
  end

  def set_current_family_member
    return if @session_revoked

    member_id = cookies.signed[:active_family_member_id]
    Current.family_member = FamilyMember.find_by(id: member_id) if member_id.present?

    if (FamilyPlates.config.hosted? || FamilyPlates.config.require_login) && Current.user.nil?
      Current.family_member = nil
      cookies.delete(:active_family_member_id)
    end

    if FamilyPlates.config.hosted?
      if Current.user.present? && Current.family_member.present? && !Current.user.household_ids.include?(Current.family_member.household_id)
        Current.family_member = nil
        cookies.delete(:active_family_member_id)
      end
    end

    Current.household = Current.family_member&.household
  end

  # No household yet: every request goes to the setup wizard. One check, including
  # controllers that skip require_authentication.
  def require_installation
    redirect_to onboarding_path unless FamilyPlates.installed?
  end

  def require_authentication
    return if Current.family_member.present?

    # Only GET and HEAD. A stored POST has no GET route, so sign-in then 404s.
    # HEAD is included because request.get? is false for it.
    session[:return_to_after_authenticating] = request.url if request.get? || request.head?

    if (FamilyPlates.config.require_login || FamilyPlates.config.hosted?) && Current.user.nil?
      redirect_to new_session_path, alert: "Please sign in to continue." and return
    end

    if FamilyPlates.config.hosted? && Current.user.present? && Current.user.households.empty?
      redirect_to new_signup_path and return
    end

    redirect_to select_profile_path and return
  end

  def require_active_family_member
    if Current.family_member.nil?
      if FamilyPlates.config.hosted? && Current.user.nil?
        redirect_to new_session_path, alert: "Please sign in to continue."
      elsif FamilyPlates.config.hosted? && Current.user.present? && Current.user.households.empty?
        redirect_to new_signup_path
      else
        redirect_to select_profile_path, alert: "Please select who is in the kitchen today."
      end
    end
  end

  # Hooks for the hosted edition, which suspends and bills households; its
  # HostedAccess concern fills them in. Declared here so they keep their place
  # in the chain above. An appliance household is never suspended or unpaid.
  def handle_suspended_household
  end

  def ensure_household_entitled!
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for_user(user)
    session_record = user.sessions.create!(
      token: SecureRandom.hex(32),
      kind: "browser",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      last_active_at: Time.current
    )
    write_permanent_signed_cookie(:session_token, session_record.token)
    write_permanent_signed_cookie(:device_kind, session_record.kind)
    Current.session = session_record
    Current.user = user

    target_household = Current.household || (FamilyPlates.config.hosted? ? user.households.first : Household.installation)
    if target_household && (member = user.family_members.find_by(household: target_household))
      start_new_session_for(member)
    end
  end

  def start_new_session_for(member)
    Current.family_member = member
    Current.household = member.household
    write_permanent_signed_cookie(:active_family_member_id, member.id)
  end

  def terminate_session
    token = cookies.signed[:session_token]
    Session.find_by_token(token)&.destroy if token.present?
    cookies.delete(:session_token)
    cookies.delete(:device_kind)
    Current.session = nil
    Current.user = nil

    Current.family_member = nil
    cookies.delete(:active_family_member_id)

    session[:forward_auth_signed_out] = true
  end

  def forward_auth_active?
    return false unless FamilyPlates.config.forward_auth_enabled?
    return false if session[:forward_auth_signed_out]
    return false unless trusted_forward_auth_proxy?(request.remote_ip)

    extract_forward_auth_email.present?
  end

  def authenticate_via_forward_auth
    email = extract_forward_auth_email
    return if email.blank?

    email = email.strip.downcase
    uid = extract_forward_auth_uid || email
    name = extract_forward_auth_name

    token = cookies.signed[:session_token]
    if token.present?
      session_record = Session.find_by_token(token)
      if session_record && !session_record.expired? && session_record.user.email == email
        session_record.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
        Current.session = session_record
        Current.user = session_record.user
        return
      end
    end

    user = User.find_or_create_from_identity(
      provider: "forward_auth",
      uid: uid,
      email: email,
      name: name
    )
    start_new_session_for_user(user)
  end

  def trusted_forward_auth_proxy?(remote_ip)
    return false if remote_ip.blank?

    require "ipaddr"
    proxies = FamilyPlates.config.forward_auth_trusted_proxies
    client_ip = IPAddr.new(remote_ip)
    proxies.any? do |trusted|
      IPAddr.new(trusted.strip).include?(client_ip)
    rescue IPAddr::Error
      false
    end
  rescue IPAddr::Error
    false
  end

  def extract_forward_auth_email
    extract_header_value(FamilyPlates.config.forward_auth_email_headers)
  end

  def extract_forward_auth_uid
    extract_header_value(FamilyPlates.config.forward_auth_user_headers)
  end

  def extract_forward_auth_name
    extract_header_value(FamilyPlates.config.forward_auth_name_headers)
  end

  def extract_header_value(candidate_headers)
    candidate_headers.each do |header_name|
      val = request.headers[header_name].presence || request.headers["HTTP_#{header_name.upcase.tr('-', '_')}"].presence
      return val if val.present?
    end
    nil
  end
end
