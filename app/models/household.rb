class Household < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  has_many :family_members, dependent: :destroy
  has_many :users, through: :family_members
  has_many :pantry_items, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :meal_plan_slots, through: :meal_plans
  has_many :device_grants, dependent: :nullify
  has_many :activity_events, dependent: :delete_all
  has_many :support_threads, dependent: :destroy
  has_many :account_deletion_requests, dependent: :destroy

  validates :name, presence: true
  validates :join_code, presence: true, uniqueness: true
  validate :time_zone_is_recognised

  # The zone the household's wall clock runs on.
  #
  # Everything stored stays UTC - that is what keeps timestamps unambiguous and
  # keeps the database out of the daylight-saving business. This is only the
  # interpretation layer: which local day "today" is, and what hour "dinner at
  # 6pm" actually falls on. Reading it through an IANA zone means DST is applied
  # for free and correctly, without a single stored value shifting.
  #
  # Blank means nobody has said yet, and UTC is the answer until they do.
  def time_zone_object
    ActiveSupport::TimeZone[time_zone.to_s.presence || DEFAULT_TIME_ZONE] ||
      ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
  end

  DEFAULT_TIME_ZONE = "UTC".freeze

  def current_time
    Time.current.in_time_zone(time_zone_object)
  end

  # The date it is *in this kitchen*. Date.current is the server's day, which
  # after 7pm in the Americas is already tomorrow.
  def today
    current_time.to_date
  end

  # Seeds the zone from a device that reported one, and only that: an existing
  # answer is never overwritten here, so a phone that travels cannot quietly
  # move the kitchen. Changing a zone already set is the settings form's job.
  def adopt_time_zone(candidate)
    return false if time_zone.present?

    zone = ActiveSupport::TimeZone[candidate.to_s]
    return false if zone.nil?

    update(time_zone: zone.name)
  end

  def suspended?
    suspended_at.present?
  end

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

  def current_meal_plan(week_date = today.beginning_of_week)
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
  before_destroy :cleanup_pay_customers, prepend: true

  def cancel_active_pay_subscriptions!
    pay_subscriptions.active.each do |sub|
      sub.cancel_now!
    rescue StandardError => e
      Rails.logger.warn "[Pay] Unable to cancel subscription #{sub.id} (#{sub.processor_id}) during household deletion: #{e.message}"
    end
  end

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

  def subscription_expires_at
    sub = payment_processor&.subscription || pay_subscriptions.order(created_at: :desc).first
    if sub
      sub.ends_at || sub.current_period_end || sub.trial_ends_at
    else
      trial_ends_at
    end
  end

  def subscription_billing_label
    return "Appliance" unless FamilyPlates.config.hosted?

    sub = payment_processor&.subscription || pay_subscriptions.order(created_at: :desc).first
    if sub
      if sub.ends_at.present?
        sub.ends_at.future? ? "Access until" : "Access expired"
      elsif sub.status == "past_due"
        past_due_grace_active? ? "Grace ends" : "Past due"
      elsif sub.status == "trialing"
        "Trial ends"
      elsif sub.active?
        "Renews"
      elsif sub.canceled?
        "Canceled"
      else
        "Expires"
      end
    elsif trial_active?
      "Trial ends"
    else
      "Trial expired"
    end
  end

  def applied_promotion_code
    promotion_code.presence ||
      (payment_processor&.subscription || pay_subscriptions.order(created_at: :desc).first)&.metadata&.dig("promotion_code")
  end

  def subscription_status
    return :appliance unless FamilyPlates.config.hosted?

    sub = payment_processor&.subscription || pay_subscriptions.order(created_at: :desc).first
    return :active if sub&.active?
    return :past_due_grace if past_due_grace_active?
    return :trialing if trial_active? || (sub.present? && sub.status == "trialing")
    return :past_due if sub&.status == "past_due"
    return :canceled if sub&.canceled?

    :expired
  end

  private

  def cleanup_pay_customers
    pay_customers.each do |customer|
      customer.destroy
    rescue StandardError => e
      Rails.logger.warn "[Pay] Unable to clean up customer #{customer.id}: #{e.message}"
    end
  end

  # A zone name arrives from a browser and from a settings form, so it is never
  # trusted: an unrecognised name would silently fall back to UTC and leave the
  # household looking configured when it is not.
  def time_zone_is_recognised
    return if time_zone.blank?
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not a recognized time zone")
  end

  def generate_join_code
    self.join_code ||= loop do
      candidate = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(join_code: candidate)
    end
  end
end
