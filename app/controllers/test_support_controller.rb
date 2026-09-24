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

    if defined?(Pay::Subscription)
      Pay::Subscription.destroy_all
      Pay::Customer.destroy_all
      Pay::PaymentMethod.destroy_all if defined?(Pay::PaymentMethod)
      Pay::Charge.destroy_all if defined?(Pay::Charge)
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

  private

  def ensure_test_environment
    head :forbidden unless Rails.env.test?
  end
end
