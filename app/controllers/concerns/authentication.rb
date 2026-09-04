module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_installation
    before_action :set_current_user
    before_action :set_current_family_member
    before_action :require_authentication
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
  end

  private

  def authenticated?
    Current.family_member.present?
  end

  # nil until someone signs in. The old `|| Household.installation` fallback
  # meant an anonymous request silently resolved to a real household, so a
  # missing scope read as working code - which is exactly the bug that becomes a
  # cross-tenant leak once a second household exists. Callers that genuinely
  # need "the household this box serves" ask Household.installation by name;
  # everything else is answering "whose data may this request see?", and for an
  # anonymous request the honest answer is nobody's.
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

    session_record = Session.find_by(token: token)
    if session_record && !session_record.expired?
      session_record.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
      Current.session = session_record
      Current.user = session_record.user
    else
      session_record&.destroy
      cookies.delete(:session_token)
    end
  end

  def set_current_family_member
    member_id = cookies.signed[:active_family_member_id]
    Current.family_member = FamilyMember.find_by(id: member_id) if member_id.present?

    if FamilyPlates.config.hosted?
      if Current.user.nil?
        Current.family_member = nil
        cookies.delete(:active_family_member_id)
      elsif Current.family_member.present? && !Current.user.household_ids.include?(Current.family_member.household_id)
        Current.family_member = nil
        cookies.delete(:active_family_member_id)
      end
    end

    Current.household = Current.family_member&.household
  end

  # Before the first household exists there is nothing to protect and no profile
  # to sign in as, so every request routes to the setup wizard. This used to be
  # asked separately in five places - here, in require_active_family_member, and
  # inline in the home, sessions and profiles controllers, which skip
  # require_authentication and so each re-checked by hand. Concentrating it is
  # Campfire's FirstRunsController lesson: the predicate was never the defect,
  # scattering it was.
  def require_installation
    redirect_to onboarding_path unless FamilyPlates.installed?
  end

  def require_authentication
    return if Current.family_member.present?

    # Only GETs are worth returning to. profiles#set consumes this with a
    # redirect, which is always a GET, so storing the URL of an expired POST
    # sent the user to a path that has no GET route - a dead 404 after a
    # successful sign-in. HEAD is included because Rails routes it to the GET
    # action while request.get? is false for it.
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

  def ensure_household_entitled!
    return unless FamilyPlates.config.hosted?
    return if current_household.nil?
    return if current_household.entitled?

    if current_family_member&.admin?
      redirect_to subscription_path, alert: "Your trial has expired. Please select a subscription to continue using your kitchen." and return
    else
      redirect_to select_profile_path, alert: "Your family's subscription is inactive. Please ask a household organizer to reactivate." and return
    end
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
    cookies.signed.permanent[:session_token] = {
      value: session_record.token, httponly: true, same_site: :lax, secure: request.ssl?
    }
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
    # secure: request.ssl? rather than a flat true - a Secure cookie is never
    # sent over plain HTTP, and plenty of these run on a LAN with no TLS at all.
    # This marks it Secure wherever TLS is actually in use and stays working
    # where it is not.
    cookies.signed.permanent[:active_family_member_id] = {
      value: member.id, httponly: true, same_site: :lax, secure: request.ssl?
    }
  end

  def terminate_session
    token = cookies.signed[:session_token]
    Session.find_by(token: token)&.destroy if token.present?
    cookies.delete(:session_token)
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
      session_record = Session.find_by(token: token)
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
