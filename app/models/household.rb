class Household < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  # A Google service account private key. Encrypted at rest so a copy of the
  # SQLite volume - a backup, a synced folder, a support bundle - does not hand
  # over access to the household's calendar.
  encrypts :google_service_account_json

  # Form-only: lets the admin calendar page offer an explicit "remove" action,
  # since a blank field there means "unchanged".
  attr_accessor :remove_google_service_account_json

  has_many :family_members, dependent: :destroy
  has_many :users, through: :family_members
  has_many :pantry_items, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :meal_plan_slots, through: :meal_plans
  has_many :device_grants, dependent: :nullify
  has_many :activity_events, dependent: :delete_all
  has_many :support_threads, dependent: :destroy

  validates :name, presence: true
  validates :join_code, presence: true, uniqueness: true

  has_secure_token :calendar_feed_token

  before_validation :generate_join_code, on: :create

  # Has this deployment been set up yet? Distinct from `installation`, which
  # answers *which* household - this only answers whether there is one at all,
  # and is the question the first-boot guard and the navbar are both asking.
  def self.installed?
    exists?
  end

  # The household this installation serves.
  #
  # An appliance install has exactly one, and it is the answer to "whose roster
  # does the front door show?" - a different question from "whose data may this
  # request see?", which is current_household and is nil until someone signs in.
  # Conflating the two is what left three implicit `|| Household.first`
  # fallbacks scattered through Authentication.
  #
  # Ordered rather than `first`, because `first` means "lowest id" and ids are
  # not creation order - in the test fixtures alone it picks the second
  # household. The oldest row is the one the setup wizard created.
  #
  # This is not a temporary crutch: it is how tenancy resolves whenever
  # REQUIRE_LOGIN is off, which is the default and stays the default. Phase 1
  # adds a session-resolved branch beside it; it does not delete this one.
  def self.installation
    order(:created_at, :id).first
  end

  def current_meal_plan(week_date = Date.current.beginning_of_week)
    meal_plans.find_or_create_by!(week_start_date: week_date)
  end

  def admin_users_with_password
    users.joins(:family_members)
         .where(family_members: { role: "admin", household_id: id })
         .where.not(password_digest: [ nil, "" ])
  end

  def can_require_login?
    admin_users_with_password.exists?
  end

  def reset_join_code!
    update!(join_code: loop do
      candidate = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(join_code: candidate)
    end)
  end

  def onboarded?
    onboarded_at.present?
  end

  def mark_onboarded!
    update!(onboarded_at: Time.current)
  end

  # Hosted Subscriptions & Billing (Pay integration)
  pay_customer default: true

  FREE_TRIAL_DAYS = 14
  PAST_DUE_GRACE_DAYS = 7

  PLANS = {
    monthly: {
      name: "Monthly",
      price: "$4",
      interval: "month",
      stripe_price_id: ENV["STRIPE_MONTHLY_PRICE_ID"].presence || "price_monthly",
      description: "Full family kitchen access, billed monthly"
    },
    annual: {
      name: "Annual",
      price: "$35",
      interval: "year",
      discount: "Save 27%",
      stripe_price_id: ENV["STRIPE_ANNUAL_PRICE_ID"].presence || "price_annual",
      description: "Best value for families, billed once a year"
    }
  }.freeze

  delegate :subscribed?, :on_trial?, :on_trial_or_subscribed?, to: :payment_processor, allow_nil: true

  def pay_customer_name
    name
  end

  def email
    admin_members = family_members.where(role: "admin")
    admin_user = admin_members.map(&:user).compact.first
    admin_user&.email || users.first&.email
  end
  alias_method :pay_customer_email, :email

  def trial_ends_at
    (created_at || Time.current) + FREE_TRIAL_DAYS.days
  end

  def trial_active?
    Time.current < trial_ends_at
  end

  def trial_days_left
    [ ((trial_ends_at - Time.current) / 1.day).ceil, 0 ].max
  end

  def past_due_grace_active?
    sub = payment_processor&.subscription
    return false unless sub&.status == "past_due"

    ref_time = sub.current_period_end || sub.updated_at
    ref_time.present? && Time.current < (ref_time + PAST_DUE_GRACE_DAYS.days)
  end

  def active_subscription?
    payment_processor&.subscribed? || false
  end

  def entitled?
    return true unless FamilyPlates.config.hosted?

    active_subscription? || trial_active? || past_due_grace_active?
  end

  def subscription_plan_key
    sub = payment_processor&.subscription
    return nil unless sub

    plan_str = sub.processor_plan.to_s.downcase
    return :monthly if plan_str == "monthly" || plan_str == PLANS[:monthly][:stripe_price_id]
    return :annual if plan_str == "annual" || plan_str == PLANS[:annual][:stripe_price_id]

    start_time = sub.current_period_start || sub.created_at
    if sub.current_period_end && start_time
      days = ((sub.current_period_end - start_time) / 1.day).round
      return :annual if days > 60
      return :monthly
    end

    :monthly
  end

  def subscription_plan_name
    key = subscription_plan_key
    return nil unless key

    PLANS[key]&.dig(:name) || key.to_s.titleize
  end

  def subscription_status
    return :appliance unless FamilyPlates.config.hosted?
    return :active if active_subscription?
    return :past_due_grace if past_due_grace_active?
    return :trialing if trial_active?
    return :past_due if payment_processor&.subscription&.status == "past_due"
    return :canceled if payment_processor&.subscription&.canceled?

    :expired
  end

  private

  def generate_join_code
    self.join_code ||= loop do
      candidate = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(join_code: candidate)
    end
  end
end
