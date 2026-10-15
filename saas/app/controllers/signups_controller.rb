# frozen_string_literal: true

class SignupsController < ApplicationController
  allow_unauthenticated_access only: %i[new create verify submit_verify]
  # Sign-up asks for Terms acceptance in its own form.
  allow_without_current_terms only: %i[new create verify submit_verify]

  MAX_HOUSEHOLD_NAME = 120
  MAX_ORGANIZER_NAME = 80
  MAX_EMAIL_LENGTH = 254
  THROTTLE_ALERT = "Too many signup attempts. Please wait a few minutes and try again."
  SIGN_IN_INSTEAD_ALERT = "We could not start signup with that email. Please sign in instead."

  # Sending the code is the expensive part: cap one address, and cap one
  # address's guesses, or a script can flood inboxes and grind the 6-character code.
  rate_limit to: 5, within: 1.hour, name: "signup_by_email", scope: "signup_attempts",
             store: LoginThrottling.store,
             by: -> { "email:#{params[:email].to_s.strip.downcase[0, MAX_EMAIL_LENGTH]}" },
             with: -> { signup_throttled! },
             only: :create, if: -> { params[:email].present? }

  rate_limit to: 20, within: 1.hour, name: "signup_by_ip", scope: "signup_attempts",
             store: LoginThrottling.store,
             by: -> { "ip:#{request.remote_ip}" },
             with: -> { signup_throttled! },
             only: :create

  rate_limit to: 10, within: 15.minutes, name: "signup_verify", scope: "signup_attempts",
             store: LoginThrottling.store,
             by: -> { "verify:#{session.dig(:pending_signup, "email")}" },
             with: -> { signup_throttled! },
             only: :submit_verify, if: -> { session.dig(:pending_signup, "email").present? }

  def new
    if authenticated? && current_household&.onboarded?
      redirect_to root_path and return
    end
  end

  def create
    household_name = params[:household_name].to_s.strip
    organizer_name = params[:organizer_name].to_s.strip
    email = params[:email].to_s.strip.downcase
    pin = params[:pin].to_s.strip
    avatar_color = FamilyMember.safe_color(params[:avatar_color].to_s.strip)
    avatar_icon = FamilyMember.safe_icon(params[:avatar_icon].to_s.strip)

    if household_name.blank? || organizer_name.blank? || email.blank? ||
        household_name.length > MAX_HOUSEHOLD_NAME || organizer_name.length > MAX_ORGANIZER_NAME ||
        email.length > MAX_EMAIL_LENGTH
      flash.now[:alert] = "Please provide your household name, your name, and a valid email address."
      render :new, status: :unprocessable_entity and return
    end

    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      flash.now[:alert] = "Please enter a valid email address."
      render :new, status: :unprocessable_entity and return
    end

    if pin.blank?
      flash.now[:alert] = "Please choose a 4-digit security PIN."
      render :new, status: :unprocessable_entity and return
    end

    unless pin.match?(/\A\d{4}\z/)
      flash.now[:alert] = "Security PIN must be exactly 4 digits."
      render :new, status: :unprocessable_entity and return
    end

    # Hosted: the organizer's own acceptance, from their own device, of the
    # version the form showed them. A form opened before the Terms changed is
    # shown again, unticked, with the version now in force.
    if (problem = signup_terms_problem(params[:terms_version], ticked: params[:accept_terms] == "1"))
      flash.now[:alert] = problem
      render :new, status: terms_assent_problem_status(problem) and return
    end

    if FamilyPlates.config.hosted?
      if current_user.present? && current_user.email == email
        record_terms_acceptance(current_user, params[:terms_version])
        household, organizer = open_household_for(
          user: current_user,
          household_name: household_name,
          organizer_name: organizer_name,
          pin: pin,
          avatar_color: avatar_color,
          avatar_icon: avatar_icon
        )
        redirect_to onboarding_recipes_path, notice: "Welcome to #{household.name}, #{organizer.name}! Let's set up your recipes." and return
      end

      FamilyPlates::OutboundEmail.validate!
      magic_code = MagicCode.create!(email: email)
      AuthenticationMailer.verification_code(magic_code).deliver_later
      flash[:magic_link_code] = magic_code.code if Rails.env.development?

      session[:pending_signup] = {
        "household_name" => household_name,
        "organizer_name" => organizer_name,
        "email" => email,
        "pin" => pin,
        "avatar_color" => avatar_color,
        "avatar_icon" => avatar_icon,
        # The version the organizer ticked the box for, checked above.
        "terms_version" => params[:terms_version]
      }
      redirect_to verify_signup_path, notice: "We sent a 6-character verification code to #{email}."
    else
      existing = User.find_by(email: email)
      if existing && current_user != existing
        # A submitted password is not proof of identity here; only an
        # already-authenticated session may reuse an existing account.
        flash.now[:alert] = SIGN_IN_INSTEAD_ALERT
        render :new, status: :unprocessable_entity and return
      end

      user = existing || User.create!(email: email, password: params[:password].presence || SecureRandom.hex(16))
      household, organizer = open_household_for(
        user: user,
        household_name: household_name,
        organizer_name: organizer_name,
        pin: pin,
        avatar_color: avatar_color,
        avatar_icon: avatar_icon
      )
      redirect_to onboarding_recipes_path, notice: "Welcome to #{household.name}, #{organizer.name}! Let's set up your recipes."
    end
  end

  def verify
    @pending = session[:pending_signup]
    unless @pending
      redirect_to new_signup_path, alert: "Please start your signup again." and return
    end
    @email = @pending["email"]
  end

  def submit_verify
    @pending = session[:pending_signup]
    unless @pending
      redirect_to new_signup_path, alert: "Please start your signup again." and return
    end

    code = params[:code].to_s.strip.upcase
    email = @pending["email"].to_s.strip.downcase
    @email = email

    # The version the organizer ticked the box for on the sign-up form. If the
    # Terms changed since, the verify page shows the version now in force with
    # an unticked box (terms_reacceptance_needed?), and that acceptance is
    # used instead. Checked before the code: nothing is used up or created.
    terms_version, ticked = @pending["terms_version"], true
    if terms_reacceptance_needed?
      terms_version, ticked = params[:terms_version], params[:accept_terms] == "1"
    end
    if (problem = signup_terms_problem(terms_version, ticked: ticked))
      flash.now[:alert] = problem
      render :verify, status: terms_assent_problem_status(problem) and return
    end

    magic_code = MagicCode.redeem(email: email, code: code)

    if magic_code
      session.delete(:pending_signup)

      user = User.find_by(email: email) || User.create!(email: email)
      record_terms_acceptance(user, terms_version)
      household, organizer = open_household_for(
        user: user,
        household_name: @pending["household_name"],
        organizer_name: @pending["organizer_name"],
        pin: @pending["pin"],
        avatar_color: @pending["avatar_color"],
        avatar_icon: @pending["avatar_icon"]
      )
      redirect_to onboarding_recipes_path, notice: "Email verified! Welcome to #{household.name}, #{organizer.name}! Let's choose your starter recipes."
    else
      BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
      flash.now[:alert] = "Invalid or expired verification code."
      render :verify, status: :unprocessable_entity
    end
  end

  private

  def signup_throttled!
    if action_name == "submit_verify" && session[:pending_signup]
      redirect_to verify_signup_path, alert: THROTTLE_ALERT
    else
      redirect_to new_signup_path, alert: THROTTLE_ALERT
    end
  end

  # Whether the verify page must ask for acceptance again: the Terms changed
  # after the organizer ticked the box on the sign-up form.
  helper_method def terms_reacceptance_needed?
    FamilyPlates.config.hosted? && session.dig(:pending_signup, "terms_version") != TermsAssent.current_version
  end

  # Whether a re-rendered sign-up form keeps the box ticked: not when the
  # Terms it showed have changed, or on a kitchen display.
  helper_method def keep_terms_ticked?
    params[:accept_terms] == "1" && params[:terms_version] == TermsAssent.current_version && !shared_device?
  end

  # Why the organizer's acceptance cannot be used, or nil. Hosted only.
  # `version` is the one the form they ticked showed them (submitted with
  # it); it must be the version now in force. Refused on a kitchen display.
  def signup_terms_problem(version, ticked:)
    return unless FamilyPlates.config.hosted?
    return TermsAssent::KIOSK_ALERT if shared_device?
    return TermsAssent::ALERT unless ticked
    return TermsAssent::VERSION_CHANGED_ALERT if version.blank? || version != TermsAssent.current_version

    nil
  end

  # Proof of consent: the version the organizer ticked the box for, and when.
  # Only ever the version checked by signup_terms_problem, which is current.
  def record_terms_acceptance(user, version)
    return if version.blank?

    TermsAssent.accept!(user, version: version, context: "signup")
  end

  # In hosted mode the user is verified by now (signed in, or just entered the
  # emailed code) and becomes the household's billing owner. The organizer
  # profile is not: anyone at the kitchen screen can select a profile.
  def open_household_for(user:, household_name:, organizer_name:, pin:, avatar_color:, avatar_icon:)
    household = Household.create!(name: household_name, billing_owner: (user if FamilyPlates.config.hosted?))
    organizer = household.family_members.create!(
      name: organizer_name,
      role: "admin",
      user: user,
      pin: pin,
      avatar_color: avatar_color.presence || FamilyMember::DEFAULT_COLOR,
      avatar_icon: avatar_icon.presence || FamilyMember::DEFAULT_ICON
    )
    start_new_session_for_user(user)
    start_new_session_for(organizer)
    [ household, organizer ]
  end
end
