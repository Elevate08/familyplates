require "active_support/testing/time_helpers"

class TestSupportController < ActionController::Base
  # The Playwright suite freezes the browser clock, but fixtures and pages are
  # built from the server's clock. Left running, the week on screen - and the
  # "cook tonight" banner - moved with the real date, and the baselines went
  # stale within days of being recorded. The server is frozen at the same moment.
  #
  # TimeHelpers keeps its stubs on the object that set them, and every request
  # gets a new controller, so one long-lived object owns the clock.
  CLOCK = Object.new.extend(ActiveSupport::Testing::TimeHelpers)

  skip_forgery_protection

  before_action :ensure_test_environment

  def reset
    FamilyPlates.config.mode = params[:mode] || "appliance"

    CLOCK.travel_back
    CLOCK.travel_to(Time.iso8601(params[:now])) if params[:now].present?

    ActiveRecord::FixtureSet.reset_cache
    ActiveRecord::FixtureSet.create_fixtures(
      Rails.root.join("test/fixtures"),
      Dir[Rails.root.join("test/fixtures/*.yml")].map { |f| File.basename(f, ".yml") }
    )

    # Clear rate-limiting store so repeated test sign-ins never get throttled
    Rails.application.config.pin_attempt_store.clear

    # In UI tests, isolate to the primary household like ApplicationSystemTestCase
    primary = Household.find_by(name: "Spencer Family") || Household.first
    Household.where.not(id: primary.id).destroy_all if primary

    # Children first: a charge points at its subscription and customer, so
    # clearing subscriptions ahead of charges fails the foreign key the first
    # time a test really pays.
    if defined?(Pay::Customer)
      Pay::Charge.delete_all
      Pay::PaymentMethod.delete_all
      Pay::Subscription.delete_all
      Pay::Customer.delete_all
    end

    render json: { status: "ok", mode: FamilyPlates.config.mode }
  end

  def set_mode
    FamilyPlates.config.mode = params[:mode] || "appliance"
    render json: { status: "ok", mode: FamilyPlates.config.mode }
  end

  def sign_in
    member = FamilyMember.find_by(name: params[:name]) || FamilyMember.where(role: "admin").first
    user = member.user || User.find_or_create_by!(email: "#{member.name.downcase.gsub(/[^a-z0-9]/, '')}@household.test")
    member.update!(user: user) unless member.user_id == user.id

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
    cookies.signed.permanent[:active_family_member_id] = {
      value: member.id, httponly: true, same_site: :lax, secure: request.ssl?
    }

    render json: { status: "ok", member_id: member.id, name: member.name, user_id: user.id }
  end

  # The platform operator is a separate account with its own session cookie,
  # not a household profile, so the household sign-in above cannot stand in.
  def sign_in_platform_admin
    admin = PlatformAdminAccount.find_or_create_by!(email: "crawler@platform.test") do |account|
      account.password = SecureRandom.hex(16)
    end
    session_record = admin.sessions.create!(ip_address: request.remote_ip, user_agent: request.user_agent)

    cookies.signed.permanent[:platform_admin_session_token] = {
      value: session_record.token, httponly: true, same_site: :lax, secure: request.ssl?
    }

    render json: { status: "ok", platform_admin_id: admin.id }
  end

  # The records the Playwright route crawl puts into parameterised paths. The
  # fixtures carry no support thread, so one is made here; everything else is
  # the primary household's fixture data.
  def crawl_records
    household = Household.find_by!(name: "Spencer Family")
    member = household.family_members.find_by!(role: "member")
    thread = household.support_threads.first_or_create!(subject: "Route crawl")

    render json: {
      household: household.id,
      recipe: household.recipes.order(:id).first!.id,
      meal_plan: household.meal_plans.order(:id).first!.id,
      family_member: member.id,
      support_thread: thread.id,
      transfer_token: member.transfer_id
    }
  end

  private

  def ensure_test_environment
    head :forbidden unless Rails.env.test?
  end
end
