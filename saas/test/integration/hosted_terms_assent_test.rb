# frozen_string_literal: true

require "test_helper"

# Hosted Terms of Service acceptance (TermsAssent): each person with their
# own sign-in accepts the current Terms for themselves - on sign-up, joining
# a household, claiming a profile, or before first use after a sign-in that
# did not ask (Google). A changed version is required of earlier acceptors
# only 30 days after a notice to them was submitted, and never blocks
# signing out, the legal documents, support or canceling.
class HostedTermsAssentTest < ActionDispatch::IntegrationTest
  NEW_VERSION = "2027-01-01"

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @household = households(:one)
    @admin = family_members(:one)
    @owner = User.create!(email: "owner@terms.test", **accepted_terms)
    @admin.update!(user: @owner)
    # In its trial, so the entitlement check lets household pages through to
    # the Terms gate.
    @household.update!(billing_owner: @owner, trial_extended_until: 1.year.from_now)
  end

  teardown { FamilyPlates.config.reset! }

  # --- Sign-up -----------------------------------------------------------------

  test "email sign-up keeps the acceptance as evidence: version, time and how" do
    post signup_path, params: {
      household_name: "The Hosted Family", organizer_name: "Alice", email: "alice@terms.test", pin: "4826", **terms_assent_params
    }
    freeze_time do
      post verify_signup_path, params: { code: MagicCode.find_by!(email: "alice@terms.test").code }

      user = User.find_by!(email: "alice@terms.test")
      acceptance = TermsAcceptance.find_by!(user_id: user.id)
      assert_equal [ TermsAssent.current_version, "signup", Time.current ],
        [ acceptance.terms_version, acceptance.context, acceptance.accepted_at ]
      assert_equal TermsAssent.current_version, user.terms_version
    end
  end

  test "a version that changed between the sign-up form and the emailed code is not recorded as accepted" do
    post signup_path, params: {
      household_name: "The Hosted Family", organizer_name: "Alice", email: "alice@terms.test", pin: "4826", **terms_assent_params
    }
    with_current_terms_version(NEW_VERSION) do
      assert_no_difference -> { User.count } => 0, -> { Household.count } => 0, -> { TermsAcceptance.count } => 0 do
        post verify_signup_path, params: { code: MagicCode.find_by!(email: "alice@terms.test").code }
      end
      assert_response :unprocessable_entity, "they are asked to accept the version actually in force first"
      assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
    end
  end

  # --- Google / OAuth ----------------------------------------------------------

  test "signing in with Google is not accepting the Terms" do
    google_user = User.find_or_create_from_identity(provider: "google", uid: "g-1", email: "google@terms.test", email_verified: true)
    @household.family_members.create!(name: "Gee", user: google_user)

    assert_nil google_user.reload.terms_version
    assert_empty TermsAcceptance.where(user_id: google_user.id)
  end

  test "a Google user with a household accepts the Terms before using it" do
    google_user = User.find_or_create_from_identity(provider: "google", uid: "g-2", email: "google2@terms.test", email_verified: true)
    member = @household.family_members.create!(name: "Gee", user: google_user)
    sign_in_user(google_user)
    sign_in_as(member)

    get meal_plans_path
    assert_redirected_to terms_acceptance_path

    get terms_acceptance_path
    assert_response :success
    assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
    assert_select "input[type=hidden][name=terms_version][value=?]", TermsAssent.current_version

    post terms_acceptance_path, params: { terms_version: TermsAssent.current_version }
    assert_response :unprocessable_entity
    assert_equal TermsAssent::ALERT, flash[:alert]
    assert_nil google_user.reload.terms_version

    post terms_acceptance_path, params: terms_assent_params
    assert_redirected_to meal_plans_path, "back to the page they were turned away from"
    acceptance = TermsAcceptance.find_by!(user_id: google_user.id)
    assert_equal [ "first_use", @household.id ], [ acceptance.context, acceptance.household_id ]

    get meal_plans_path
    assert_response :redirect
    assert_no_match %r{terms_acceptance}, response.location
  end

  test "a Google user without a household goes to sign-up, which asks for acceptance itself" do
    google_user = User.find_or_create_from_identity(provider: "google", uid: "g-3", email: "google3@terms.test", email_verified: true)
    sign_in_user(google_user)

    get root_path
    assert_redirected_to new_signup_path

    post signup_path, params: { household_name: "Gees", organizer_name: "Gee", email: google_user.email, pin: "4826" }
    assert_response :unprocessable_entity
    assert_equal 0, google_user.reload.households.count

    post signup_path, params: { household_name: "Gees", organizer_name: "Gee", email: google_user.email, pin: "4826", **terms_assent_params }
    assert_redirected_to onboarding_recipes_path
    assert_equal [ "signup" ], TermsAcceptance.where(user_id: google_user.id).pluck(:context)
  end

  # --- Joining a household -----------------------------------------------------

  test "joining a household requires the joiner's own unticked acceptance" do
    joiner = User.create!(email: "joiner@terms.test")
    sign_in_user(joiner)

    get join_path
    assert_select "input[type=checkbox][name=accept_terms]:not([checked])"

    assert_no_difference -> { FamilyMember.count } do
      post join_path, params: { join_code: @household.join_code, terms_version: TermsAssent.current_version }
    end
    assert_response :unprocessable_entity
    assert_equal TermsAssent::ALERT, flash[:alert]

    assert_no_difference -> { FamilyMember.count } do
      post join_path, params: { join_code: @household.join_code, **terms_assent_params(version: "2020-01-01") }
    end
    assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]

    assert_difference -> { @household.family_members.count } => 1 do
      post join_path, params: { join_code: @household.join_code, **terms_assent_params }
    end
    assert_equal TermsAssent.current_version, joiner.reload.terms_version
    acceptance = TermsAcceptance.find_by!(user_id: joiner.id)
    assert_equal [ "join", @household.id ], [ acceptance.context, acceptance.household_id ]
    assert_equal @owner, @household.reload.billing_owner, "joining confers no billing authority"
  end

  test "someone who already accepted the current Terms joins without being asked again" do
    joiner = User.create!(email: "joiner@terms.test", **accepted_terms)
    sign_in_user(joiner)

    get join_path
    assert_select "input[name=accept_terms]", false

    post join_path, params: { join_code: @household.join_code }
    assert_redirected_to root_path
    assert_empty TermsAcceptance.where(user_id: joiner.id), "nothing new was agreed to"
  end

  # --- Claiming a profile ------------------------------------------------------

  test "claiming a profile requires the claimant's own acceptance and moves no billing authority" do
    claimant = User.create!(email: "claimant@terms.test")
    sign_in_user(claimant)
    token = @admin.transfer_id

    get transfer_path(token: token)
    assert_select "input[type=checkbox][name=accept_terms]:not([checked])"

    post claim_transfer_path(token: token), params: { terms_version: TermsAssent.current_version }
    assert_response :unprocessable_entity
    assert_equal @owner, @admin.reload.user, "not claimed without acceptance"

    post claim_transfer_path(token: token), params: terms_assent_params
    assert_equal claimant, @admin.reload.user
    assert_equal [ "claim" ], TermsAcceptance.where(user_id: claimant.id).pluck(:context)
    assert_equal @owner, @household.reload.billing_owner
    assert_empty TermsAcceptance.where(user_id: @owner.id).where(context: "claim")
  end

  test "an invalid claim records no acceptance" do
    claimant = User.create!(email: "claimant@terms.test")
    sign_in_user(claimant)
    token = @admin.transfer_id
    @admin.update!(user: User.create!(email: "someone-else@terms.test", **accepted_terms)) # link now stale

    post claim_transfer_path(token: token), params: terms_assent_params

    assert_redirected_to select_profile_path
    assert_empty TermsAcceptance.where(user_id: claimant.id)
    assert_nil claimant.reload.terms_version
  end

  # --- Changed Terms -----------------------------------------------------------

  test "a changed version is held, with an in-app notice, until 30 days after a notice was submitted" do
    sign_in_user(@owner)
    sign_in_as(@admin)

    with_current_terms_version(NEW_VERSION) do
      get meal_plans_path
      follow_redirect!
      assert_response :success, "no proof of notice: not enforced"
      assert_select "[data-testid=terms-change-notice] a[href=?]", terms_acceptance_path

      submitted = Time.current.change(usec: 0)
      notice = TermsNotice.create!(user_id: @owner.id, terms_version: NEW_VERSION, previous_terms_version: Legal::TERMS_VERSION,
        state: "submitted", submitted_at: submitted, stated_enforcement_at: TermsAssent.notice_period_end(@owner, submitted))
      enforced_from = notice.reload.enforcement_at
      assert_operator enforced_from, :>=, submitted + 30.days

      # Signed in again each time: a month idle ends a session.
      travel_to enforced_from - 1.second do
        sign_in_user(@owner)
        sign_in_as(@admin)
        get meal_plans_path
        assert_no_match %r{terms_acceptance}, response.location.to_s, "still inside the notice period"
      end

      travel_to enforced_from do
        sign_in_user(@owner)
        sign_in_as(@admin)
        get meal_plans_path
        assert_redirected_to terms_acceptance_path
        assert_equal notice.enforcement_at, TermsNotice.enforcement_at_for(@owner)

        post terms_acceptance_path, params: terms_assent_params(version: NEW_VERSION)
        assert_equal NEW_VERSION, @owner.reload.terms_version
        assert_equal "reacceptance", TermsAcceptance.where(user_id: @owner.id).order(:accepted_at).last.context
      end
    end
  end

  test "declining changed Terms: the billing owner can ask support for an adjusted refund, and cancel themselves" do
    sign_in_user(@owner)
    sign_in_as(@admin)

    with_current_terms_version(NEW_VERSION) do
      get terms_acceptance_path
      assert_select "[data-testid=terms-decline]" do |section|
        assert_includes section.text.squish,
          "If you decline the updated Terms, you can email support@familyplates.org to request an adjusted refund for unused prepaid service."
        assert_select "a[href=?]", "mailto:support@familyplates.org"
        assert_select "a[href=?]", subscription_path
      end
    end
  end

  test "declining changed Terms: someone who does not pay is offered account deletion, not a refund" do
    member_user = User.create!(email: "member@terms.test", **accepted_terms)
    member = @household.family_members.create!(name: "Member", user: member_user)
    sign_in_user(member_user)
    sign_in_as(member)

    with_current_terms_version(NEW_VERSION) do
      get terms_acceptance_path
      assert_select "[data-testid=terms-decline]" do |section|
        assert_includes section.text.squish, "you can email support@familyplates.org to ask for your account to be deleted"
        assert_no_match(/refund/i, section.text)
      end
    end
  end

  test "a first acceptance has no decline section: there is nothing to cancel or refund yet" do
    blank = User.create!(email: "first@terms.test")
    member = @household.family_members.create!(name: "First", user: blank)
    sign_in_user(blank)
    sign_in_as(member)

    get terms_acceptance_path
    assert_select "[data-testid=terms-decline]", count: 0
  end

  test "a person who never accepted any version is gated immediately" do
    blank = User.create!(email: "blank@terms.test")
    member = @household.family_members.create!(name: "Blank", user: blank)
    sign_in_user(blank)
    sign_in_as(member)

    get recipes_path
    assert_redirected_to terms_acceptance_path

    get recipes_path, as: :json
    assert_response :forbidden
    assert_equal "terms_acceptance_required", response.parsed_body["error"]
  end

  test "an outdated acceptance cannot be submitted against a newer version" do
    blank = User.create!(email: "blank@terms.test")
    member = @household.family_members.create!(name: "Blank", user: blank)
    sign_in_user(blank)
    sign_in_as(member)

    with_current_terms_version(NEW_VERSION) do
      post terms_acceptance_path, params: terms_assent_params(version: Legal::TERMS_VERSION)
      assert_response :unprocessable_entity
      assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]
      assert_nil blank.reload.terms_version
    end
    assert_not TermsAssent.accept!(blank, version: "", context: "first_use")
    assert_raises(ArgumentError) { TermsAssent.accept!(blank, version: Legal::TERMS_VERSION, context: "login") }
  end

  test "while gated, sign-out, the legal pages, support, account data and cancellation stay reachable without loops" do
    @owner.update!(terms_version: nil, terms_accepted_at: nil)
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscribe(plan: "monthly", ends_at: nil)
    sign_in_user(@owner)
    sign_in_as(@admin)

    get meal_plans_path
    assert_redirected_to terms_acceptance_path
    get terms_acceptance_path
    assert_response :success, "the acceptance page never redirects to itself"

    [ terms_path, privacy_path, support_threads_path, subscription_path, account_data_path ].each do |path|
      get path
      assert_response :success, "#{path} must stay reachable before accepting"
    end

    delete subscription_path
    assert_redirected_to subscription_path
    assert_match "canceled", flash[:notice]

    post subscription_path, params: { plan: "monthly" }
    assert_redirected_to terms_acceptance_path, "starting a new subscription waits for acceptance"

    delete session_path
    assert_response :redirect
    assert_no_match %r{terms_acceptance}, response.location
  end

  test "a kitchen display cannot accept the Terms for anyone" do
    blank = User.create!(email: "blank@terms.test")
    member = @household.family_members.create!(name: "Blank", user: blank)
    sign_in_user(blank)
    sign_in_as(member)
    blank.sessions.update_all(kind: "kiosk")

    post terms_acceptance_path, params: terms_assent_params
    assert_response :forbidden
    assert_nil blank.reload.terms_version
  end

  # --- Own device only -----------------------------------------------------------
  # A kitchen display is signed in as someone, but whoever stands at it is not
  # necessarily them. No flow that brings a personal account into a household
  # runs from one, whether or not that account already accepted.

  test "a kitchen display cannot join a household, accepting or not" do
    [ User.create!(email: "kiosk-blank@terms.test"), User.create!(email: "kiosk-current@terms.test", **accepted_terms),
      User.create!(email: "kiosk-stale@terms.test", **accepted_terms(version: "2020-01-01")) ].each do |user|
      kiosk_sign_in(user)
      before = user.terms_version

      assert_no_difference -> { FamilyMember.count } => 0, -> { TermsAcceptance.count } => 0 do
        post join_path, params: { join_code: @household.join_code, **terms_assent_params }
      end
      assert_response :forbidden, user.email
      assert_equal TermsAssent::KIOSK_ALERT, flash[:alert]
      assert before == user.reload.terms_version, "#{user.email}: acceptance unchanged"
      assert_empty user.family_members
    end
  end

  test "a kitchen display cannot claim a profile, accepting or not" do
    token = @admin.transfer_id
    [ User.create!(email: "kiosk-blank@terms.test"), User.create!(email: "kiosk-current@terms.test", **accepted_terms) ].each do |user|
      kiosk_sign_in(user)

      assert_no_difference -> { TermsAcceptance.count } do
        post claim_transfer_path(token: token), params: terms_assent_params
      end
      assert_response :forbidden, user.email
      assert_equal @owner, @admin.reload.user, "not claimed from a kitchen display"
    end
  end

  test "a kitchen display cannot sign up a household, signed in or by email" do
    user = User.create!(email: "kiosk-signup@terms.test")
    kiosk_sign_in(user)

    assert_no_difference -> { Household.count } => 0, -> { TermsAcceptance.count } => 0, -> { MagicCode.count } => 0 do
      post signup_path, params: { household_name: "Kiosk", organizer_name: "K", email: user.email, pin: "4826", **terms_assent_params }
      assert_response :forbidden
      post signup_path, params: { household_name: "Kiosk", organizer_name: "K", email: "other@terms.test", pin: "4826", **terms_assent_params }
      assert_response :forbidden
    end
    assert_equal TermsAssent::KIOSK_ALERT, flash[:alert]
    assert_nil user.reload.terms_version
  end

  test "the own-device check runs before any acceptance is recorded, even if a flow skips asking" do
    user = User.create!(email: "kiosk-direct@terms.test")
    Current.session = kiosk_sign_in(user)
    Current.user = user
    controller = JoinsController.new
    controller.params = ActionController::Parameters.new(terms_assent_params)
    assert_raises(ActionController::BadRequest) do
      controller.send(:record_terms_assent!, context: "join", household: @household)
    end
    assert_nil user.reload.terms_version
  ensure
    Current.reset
  end

  # --- Sign-up shows and binds its version ---------------------------------------

  test "the sign-up form submits the version it shows" do
    get new_signup_path
    assert_select "form input[type=hidden][name=terms_version][value=?]", TermsAssent.current_version
    assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
  end

  test "a signed-in sign-up opened before the Terms changed is refused and shown again unticked" do
    user = User.create!(email: "signedin@terms.test")
    sign_in_user(user)
    get new_signup_path
    shown = css_select("input[name=terms_version]").first["value"]

    with_current_terms_version(NEW_VERSION) do
      assert_no_difference -> { Household.count } => 0, -> { TermsAcceptance.count } => 0 do
        post signup_path, params: { household_name: "Stale", organizer_name: "S", email: user.email, pin: "4826",
          accept_terms: "1", terms_version: shown }
      end
      assert_response :unprocessable_entity
      assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]
      assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
      assert_select "input[type=hidden][name=terms_version][value=?]", NEW_VERSION
      assert_nil user.reload.terms_version

      post signup_path, params: { household_name: "Fresh", organizer_name: "S", email: user.email, pin: "4826",
        **terms_assent_params(version: NEW_VERSION) }
      assert_redirected_to onboarding_recipes_path
      assert_equal [ [ NEW_VERSION, "signup" ] ], TermsAcceptance.where(user_id: user.id).pluck(:terms_version, :context)
    end
  end

  test "a signed-in Google sign-up without a version is refused" do
    google_user = User.find_or_create_from_identity(provider: "google", uid: "g-4", email: "google4@terms.test", email_verified: true)
    sign_in_user(google_user)

    post signup_path, params: { household_name: "Gees", organizer_name: "Gee", email: google_user.email, pin: "4826", accept_terms: "1" }
    assert_response :unprocessable_entity
    assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]
    assert_empty TermsAcceptance.where(user_id: google_user.id)
  end

  test "an email sign-up opened before the Terms changed sends no code" do
    shown = TermsAssent.current_version
    with_current_terms_version(NEW_VERSION) do
      assert_no_difference -> { MagicCode.count } do
        post signup_path, params: { household_name: "Stale", organizer_name: "S", email: "stale@terms.test", pin: "4826",
          accept_terms: "1", terms_version: shown }
      end
      assert_response :unprocessable_entity
      assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]
      assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
    end
  end

  test "Terms that change before the emailed code is entered are accepted on the verify page first" do
    post signup_path, params: { household_name: "Between", organizer_name: "B", email: "between@terms.test", pin: "4826",
      **terms_assent_params }
    assert_equal TermsAssent.current_version, session[:pending_signup]["terms_version"], "the checked version is carried"
    code = MagicCode.find_by!(email: "between@terms.test").code

    with_current_terms_version(NEW_VERSION) do
      get verify_signup_path
      assert_select "input[type=checkbox][name=accept_terms]:not([checked])"
      assert_select "input[type=hidden][name=terms_version][value=?]", NEW_VERSION

      assert_no_difference -> { Household.count } => 0, -> { User.count } => 0 do
        post verify_signup_path, params: { code: code }
        assert_response :unprocessable_entity
        assert_equal TermsAssent::ALERT, flash[:alert]
        post verify_signup_path, params: { code: code, accept_terms: "1", terms_version: Legal::TERMS_VERSION }
        assert_equal TermsAssent::VERSION_CHANGED_ALERT, flash[:alert]
      end
      assert MagicCode.exists?(email: "between@terms.test"), "the code is not used up"

      post verify_signup_path, params: { code: code, **terms_assent_params(version: NEW_VERSION) }
      assert_redirected_to onboarding_recipes_path
      user = User.find_by!(email: "between@terms.test")
      assert_equal [ [ NEW_VERSION, "signup" ] ], TermsAcceptance.where(user_id: user.id).pluck(:terms_version, :context)
    end
  end

  test "the verify page asks nothing more when the Terms have not changed" do
    post signup_path, params: { household_name: "Same", organizer_name: "S", email: "same@terms.test", pin: "4826", **terms_assent_params }
    get verify_signup_path
    assert_select "input[name=accept_terms]", false

    post verify_signup_path, params: { code: MagicCode.find_by!(email: "same@terms.test").code }
    assert_redirected_to onboarding_recipes_path
  end

  test "the acceptance page sends anyone not signed in to sign in" do
    get terms_acceptance_path
    assert_redirected_to new_session_path
  end

  # --- Evidence ----------------------------------------------------------------

  test "acceptance evidence is append-only and survives the user's deletion" do
    TermsAssent.accept!(@owner, version: Legal::TERMS_VERSION, context: "first_use")
    acceptance = TermsAcceptance.find_by!(user_id: @owner.id)

    assert_raises(ActiveRecord::ReadOnlyRecord) { acceptance.update!(terms_version: "forged") }
    @household.destroy!
    @owner.destroy!
    assert TermsAcceptance.exists?(acceptance.id)
    assert_equal %w[accepted_at context created_at household_id id terms_version updated_at user_id],
      TermsAcceptance.column_names.sort, "no email, IP address or household content is kept"
  end

  # --- Appliance ---------------------------------------------------------------

  test "an appliance asks for, checks and records no Terms" do
    FamilyPlates.config.mode = "appliance"
    joiner = User.create!(email: "joiner@terms.test")
    sign_in_user(joiner)

    get join_path
    assert_select "input[name=accept_terms]", false
    post join_path, params: { join_code: @household.join_code }
    assert_redirected_to root_path
    member = @household.family_members.find_by!(user: joiner)

    get meal_plans_path
    assert_no_match %r{terms_acceptance}, response.location.to_s
    get terms_acceptance_path
    assert_redirected_to root_path
    assert_nil joiner.reload.terms_version
    assert_empty TermsAcceptance.all
    assert member
  end

  test "an appliance kitchen display joins as before" do
    FamilyPlates.config.mode = "appliance"
    joiner = User.create!(email: "appliance-kiosk@terms.test")
    kiosk_sign_in(joiner)

    post join_path, params: { join_code: @household.join_code }
    assert_redirected_to root_path
    assert @household.family_members.exists?(user: joiner)
    assert_empty TermsAcceptance.all
  end

  private

  def kiosk_sign_in(user)
    sign_in_user(user).tap { |record| record.update!(kind: "kiosk") }
  end
end
