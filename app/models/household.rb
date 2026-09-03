class Household < ApplicationRecord
  # A Google service account private key. Encrypted at rest so a copy of the
  # SQLite volume - a backup, a synced folder, a support bundle - does not hand
  # over access to the household's calendar.
  encrypts :google_service_account_json

  # Form-only: lets the admin calendar page offer an explicit "remove" action,
  # since a blank field there means "unchanged".
  attr_accessor :remove_google_service_account_json

  has_many :family_members, dependent: :destroy
  has_many :pantry_items, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :meal_plan_slots, through: :meal_plans

  validates :name, presence: true

  def current_meal_plan(week_date = Date.current.beginning_of_week)
    meal_plans.find_or_create_by!(week_start_date: week_date)
  end
end
