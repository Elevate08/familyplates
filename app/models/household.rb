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

  validates :name, presence: true
  validates :join_code, presence: true, uniqueness: true

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

  private

  def generate_join_code
    self.join_code ||= loop do
      candidate = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      break candidate unless self.class.exists?(join_code: candidate)
    end
  end
end
