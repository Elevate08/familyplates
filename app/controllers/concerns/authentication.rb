module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_family_member
    before_action :require_authentication
    before_action :require_active_family_member
    helper_method :authenticated?, :current_household, :current_family_member
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_active_family_member, **options
    end
  end

  private

  def authenticated?
    Current.family_member.present?
  end

  def current_household
    Current.household || Household.first
  end

  def current_family_member
    Current.family_member
  end

  def set_current_family_member
    member_id = cookies.signed[:active_family_member_id]
    if member_id.present?
      Current.family_member = FamilyMember.find_by(id: member_id)
      Current.household = Current.family_member&.household || Household.first
    else
      Current.family_member = nil
      Current.household = Household.first
    end
  end

  # Before the first household exists there is nothing to protect and no profile
  # to sign in as, so the setup wizard is open and everything else routes to it.
  # Once a household exists, controllers opt out one action at a time with
  # allow_unauthenticated_access — never by controller name, which cannot express
  # "these two actions but not the other eight".
  def require_authentication
    if Household.none?
      redirect_to onboarding_path and return unless request.path.start_with?("/onboarding")
      return
    end

    return if Current.family_member.present?

    # Only GETs are worth returning to. profiles#set consumes this with a
    # redirect, which is always a GET, so storing the URL of an expired POST
    # sent the user to a path that has no GET route - a dead 404 after a
    # successful sign-in. HEAD is included because Rails routes it to the GET
    # action while request.get? is false for it.
    session[:return_to_after_authenticating] = request.url if request.get? || request.head?
    redirect_to select_profile_path and return
  end

  def require_active_family_member
    return if Household.none?

    if Current.family_member.nil?
      redirect_to select_profile_path, alert: "Please select who is in the kitchen today."
    end
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(member)
    Current.family_member = member
    Current.household = member.household
    cookies.signed.permanent[:active_family_member_id] = { value: member.id, httponly: true, same_site: :lax }
  end

  def terminate_session
    Current.family_member = nil
    cookies.delete(:active_family_member_id)
  end
end
