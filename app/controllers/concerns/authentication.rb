require "ipaddr"

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
    before_action :require_current_terms
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

    # Also reachable by someone who has yet to accept changed hosted Terms:
    # the same pages a suspended household keeps (signing out, the legal
    # documents, support, account data) are the ones they must keep.
    def allow_suspended_access(**options)
      skip_before_action :handle_suspended_household, **options
      skip_before_action :require_active_family_member, **options
      skip_before_action :ensure_household_entitled!, **options, raise: false
      skip_before_action :require_current_terms, **options, raise: false
    end

    # Pages a signed-in user can reach before accepting the hosted Terms:
    # signing in, and the flows that ask for acceptance themselves.
    def allow_without_current_terms(**options)
      skip_before_action :require_current_terms, **options, raise: false
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
    if (email = trusted_forward_auth_email)
      authenticate_via_forward_auth(email)
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

  # Whether a household found some other way than the signed-in profile
  # (a calendar feed token) may have its content served. Always, here.
  def household_content_available?(_household)
    true
  end

  # Hosted Terms of Service acceptance, filled in by HostedAccess. An
  # appliance has no Terms: nothing is required, checked or recorded.
  def require_current_terms
  end

  # Why the submitted Terms acceptance cannot be used, or nil when none is
  # needed or it is valid. For joining a household and claiming a profile.
  def terms_assent_problem
  end

  # The response status for a terms_assent_problem.
  def terms_assent_problem_status(_problem)
    :unprocessable_entity
  end

  def record_terms_assent!(context:, household:)
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for_user(user)
    target_household = Current.household || (FamilyPlates.config.hosted? ? user.households.first : Household.installation)
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
    Current.family_member = nil
    Current.household = nil
    cookies.delete(:active_family_member_id)

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

  # The identity email from the proxy's headers, or nil unless forward-auth is
  # on and the connecting hop is a trusted proxy.
  def trusted_forward_auth_email
    return unless FamilyPlates.config.forward_auth_enabled?
    return if session[:forward_auth_signed_out]

    email = extract_forward_auth_email
    return if email.blank?

    peer = forward_auth_peer_ip
    return email if trusted_forward_auth_proxy?(peer)

    Rails.logger.warn("[auth] forward_auth_untrusted_peer peer=#{forward_auth_peer_label(peer)}")
    nil
  end

  # The address that connected to the app, not request.remote_ip: remote_ip is
  # read from X-Forwarded-For, which any client on a private network can set.
  # In the Docker image, requests normally arrive through Thruster, so the TCP
  # peer is loopback and Thruster appends the address that connected to it as
  # the last X-Forwarded-For entry. That entry is the hop to check. A connection
  # straight to Puma's own port (3000) has its own address and is checked as is.
  def forward_auth_peer_ip
    peer = parse_peer_ip(request.remote_addr)
    forwarded = request.get_header("HTTP_X_FORWARDED_FOR")
    return peer unless peer && FamilyPlates.host_address?(peer) && peer.loopback? && !forwarded.nil?

    parse_peer_ip(forwarded.split(",", -1).last)
  end

  def parse_peer_ip(value)
    FamilyPlates.native_ip(IPAddr.new(value.to_s.strip))
  rescue IPAddr::Error
    nil
  end

  def forward_auth_peer_label(peer)
    return "unparseable" if peer.nil?

    FamilyPlates.host_address?(peer) ? peer.to_s : "range:#{peer}/#{peer.prefix}"
  end

  def authenticate_via_forward_auth(email)
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
      # Identity headers are only used after trusted_forward_auth_email confirmed the
      # trusted proxy sent them; the proxy has already authenticated the user.
      email_verified: true,
      name: name
    )
    start_new_session_for_user(user)
  end

  def trusted_forward_auth_proxy?(peer)
    # Load-bearing: IPAddr#== ignores the prefix, so a range hop must be refused here.
    return false if peer.nil? || !FamilyPlates.host_address?(peer)

    FamilyPlates.config.forward_auth_proxies.hosts.include?(peer)
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
