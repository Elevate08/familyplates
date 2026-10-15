# Suspension and billing checks for every household page. Fills in the hooks
# the core Authentication concern leaves empty.
module HostedAccess
  extend ActiveSupport::Concern

  TRIAL_ENDED_OWNER_ALERT = "Your free trial has ended. Subscribe to keep using your household."
  TRIAL_ENDED_MEMBER_ALERT = "Your free trial has ended. Ask your household owner to subscribe to keep using your household."
  SUBSCRIPTION_INACTIVE_OWNER_ALERT = "Your subscription is not active. Renew it to keep using your household."
  SUBSCRIPTION_INACTIVE_MEMBER_ALERT = "Your household's subscription is not active. Ask your household owner to renew it."
  PAYMENT_PENDING_ALERT = "We are confirming whether your subscription payment went through. Your household opens as soon as it is confirmed."

  included do
    helper_method :household_billing_owner_session?, :household_cancellation_session?
  end

  private

  def handle_suspended_household
    return unless current_household&.suspended?

    redirect_to suspended_path
  end

  # A household without a trial, paid term or renewal grace keeps no kitchen:
  # every page that reads or changes household content sends its people to
  # the subscription page, which says what to do and, to the billing owner
  # only, offers the plans. Nothing is deleted. Pages that skip this keep
  # signing in and out, choosing a profile, the subscription itself, the
  # legal documents, support and the owner's export and deletion request.
  def ensure_household_entitled!
    return unless FamilyPlates.config.hosted?
    return if current_household.nil?
    return if current_household.entitled?

    message = household_unentitled_alert
    if request.format.json?
      render json: { error: "subscription_required", message: message, redirect_url: subscription_path }, status: :forbidden
    else
      redirect_to subscription_path, alert: message, status: :see_other
    end
  end

  # For a controller that finds its household by something other than the
  # signed-in profile, such as a calendar feed token.
  def household_content_available?(household)
    !FamilyPlates.config.hosted? || household.entitled?
  end

  # The signed-in person, on their own profile and not a shared kitchen
  # display, owns this household's billing. Only they are offered Subscribe.
  def household_billing_owner_session?
    user = current_user
    return false if user.nil? || Current.session.nil? || Current.session.kiosk?
    return false unless current_family_member&.user_id == user.id

    current_household&.billing_owner?(user) || false
  end

  # Who may cancel the subscription: the billing owner, or, for a household
  # recorded before billing owners were (none set until support recovers
  # one), an organizer on their own profile and device. Only cancelling:
  # subscribing and the billing portal still wait for a billing owner.
  def household_cancellation_session?
    return true if household_billing_owner_session?
    return false unless current_household && current_household.billing_owner_user_id.nil?

    user = current_user
    return false if user.nil? || Current.session.nil? || Current.session.kiosk?

    member = current_family_member
    member&.user_id == user.id && member.admin?
  end

  def household_unentitled_alert
    household = current_household
    # Pending first, even for a household that paid before: one renewing
    # after its term lapsed must not be told to pay again.
    return PAYMENT_PENDING_ALERT if household.subscription_payment_pending?

    owner = household_billing_owner_session?
    if household.paid_conversion?
      owner ? SUBSCRIPTION_INACTIVE_OWNER_ALERT : SUBSCRIPTION_INACTIVE_MEMBER_ALERT
    else
      owner ? TRIAL_ENDED_OWNER_ALERT : TRIAL_ENDED_MEMBER_ALERT
    end
  end

  # A signed-in person who has never agreed to the hosted Terms, or whose
  # notice period for a changed version has ended, accepts them before using
  # a household. Pages that skip this (allow_suspended_access,
  # allow_without_current_terms) keep sign-in and sign-out, the legal
  # documents, support, account data and subscription cancellation open.
  #
  # Only someone with a household is stopped here. Someone without one is on
  # their way to sign-up or a join code, which ask for acceptance themselves.
  def require_current_terms
    return unless FamilyPlates.config.hosted?
    return unless TermsAssent.acceptance_required?(current_user)
    return unless current_user.family_members.exists?

    if request.format.json?
      render json: { error: "terms_acceptance_required", redirect_url: terms_acceptance_path }, status: :forbidden
    else
      session[:return_to_after_terms] = request.fullpath if request.get? || request.head?
      redirect_to terms_acceptance_path, status: :see_other
    end
  end

  # Checked by every flow that asks for a person's own acceptance (joining,
  # claiming a profile, sign-up, the acceptance page) before it records
  # anything or changes a membership. A kitchen display is refused whether or
  # not its user has already accepted: those flows bring a personal account
  # into a household, which only that person's own device may do.
  def terms_assent_problem
    return unless FamilyPlates.config.hosted?
    return TermsAssent::KIOSK_ALERT if shared_device?
    return if TermsAssent.current?(current_user)
    return TermsAssent::VERSION_CHANGED_ALERT if params[:terms_version] != TermsAssent.current_version
    return TermsAssent::ALERT if params[:accept_terms] != "1"

    nil
  end

  def terms_assent_problem_status(problem)
    problem == TermsAssent::KIOSK_ALERT ? :forbidden : :unprocessable_entity
  end

  # Records the person's own acceptance, given in the form terms_assent_problem
  # checked. Nothing to record if they had already accepted this version.
  # Raises on a kitchen display, rolling back the caller's transaction, in
  # case a flow ever records without asking terms_assent_problem first.
  def record_terms_assent!(context:, household:)
    return unless FamilyPlates.config.hosted?
    raise ActionController::BadRequest, TermsAssent::KIOSK_ALERT if shared_device?
    return if TermsAssent.current?(current_user)

    TermsAssent.accept!(current_user, version: params[:terms_version], context: context, household: household)
  end

  def shared_device?
    Current.session&.kiosk? || false
  end

  # Support conversations are a person's own, not a shared kitchen display's.
  def forbid_kiosk_support_access
    redirect_to root_path, alert: "Kiosk devices cannot use support." if shared_device?
  end
end
