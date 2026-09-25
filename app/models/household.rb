class Household < ApplicationRecord
  DEFAULT_TIME_ZONE = "UTC".freeze

  attribute :id, default: -> { SecureRandom.uuid }

  has_many :family_members, dependent: :destroy
  has_many :users, through: :family_members
  has_many :pantry_items, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :meal_plan_slots, through: :meal_plans
  has_many :device_grants, dependent: :nullify
  has_many :activity_events, dependent: :delete_all

  has_secure_token :calendar_feed_token

  before_validation :generate_join_code, on: :create

  validates :name, presence: true
  validates :join_code, presence: true, uniqueness: true
  validate :time_zone_is_recognised

  # IANA zone for "today" and "dinner at 6pm". Stored times stay UTC so DST
  # never shifts a row. Blank means UTC until someone sets a zone.
  def time_zone_object
    ActiveSupport::TimeZone[time_zone.to_s.presence || DEFAULT_TIME_ZONE] ||
      ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
  end

  def current_time
    Time.current.in_time_zone(time_zone_object)
  end

  # Kitchen-local date. Date.current is the server's day, already tomorrow after 7pm in the Americas.
  def today
    current_time.to_date
  end

  # Seed only. Never overwrites a zone already set, so a traveling phone cannot move the kitchen.
  def adopt_time_zone(candidate)
    return false if time_zone.present?

    zone = ActiveSupport::TimeZone[candidate.to_s]
    return false if zone.nil?

    update(time_zone: zone.name)
  end

  # Whether any household exists. `installation` answers which one.
  def self.installed?
    exists?
  end

  # Whose roster the front door shows. Not current_household, which is nil
  # until sign-in. Ordered by created_at: `first` is lowest id, and fixture
  # ids are not creation order. This stays while REQUIRE_LOGIN is off.
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
    update!(join_code: unique_join_code)
  end

  def onboarded?
    onboarded_at.present?
  end

  def mark_onboarded!
    update!(onboarded_at: Time.current)
  end

  def email
    users.joins(:family_members)
         .where(family_members: { role: "admin", household_id: id })
         .first&.email || users.first&.email
  end

  private

  def unique_join_code
    loop do
      candidate = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(join_code: candidate)
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
    self.join_code ||= unique_join_code
  end
end
