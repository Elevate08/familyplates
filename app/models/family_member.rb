class FamilyMember < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  DEFAULT_COLOR = "#F97316"
  DEFAULT_ICON = "chef-hat"

  belongs_to :household
  belongs_to :user, optional: true
  has_many :recipe_requests, dependent: :destroy
  has_many :meal_plan_slots, dependent: :nullify

  AVATAR_COLORS = [
    "#F97316", # Orange (Warm Carrot / Brand)
    "#3B82F6", # Blue (Ocean)
    "#10B981", # Emerald (Sage)
    "#F59E0B", # Amber (Golden)
    "#EF4444", # Red (Chili)
    "#8B5CF6", # Purple (Plum)
    "#EC4899", # Pink (Berry)
    "#14B8A6", # Teal (Mint)
    "#6366F1", # Indigo (Twilight)
    "#84CC16", # Lime (Olive)
    "#06B6D4", # Cyan (Sky)
    "#64748B"  # Slate (Graphite)
  ].freeze

  AVATAR_ICONS = %w[chef-hat utensils heart star smile flame sparkles award].freeze

  # Stores only a digest. `pin` is a write-only virtual attribute, so a PIN that
  # has been saved cannot be read back out of the record, out of a database copy,
  # or out of a page that renders the model.
  has_secure_password :pin, validations: false

  TRANSFER_LINK_EXPIRY_DURATION = 4.hours

  def transfer_id
    signed_id(purpose: :transfer, expires_in: TRANSFER_LINK_EXPIRY_DURATION)
  end

  def self.find_by_transfer_id(id)
    find_signed(id, purpose: :transfer)
  end

  def transfer_to!(new_user)
    update!(user: new_user)
  end

  validates :name, presence: true
  validates :user_id, uniqueness: { scope: :household_id }, allow_nil: true
  # allow_blank, because `pin` reads back as nil on a record loaded from the
  # database and blank on a form submitted without changing it - only a PIN
  # actually being set is format-checked. Presence is asserted against the
  # digest instead, which survives a reload.
  validates :pin, format: { with: /\A\d{4}\z/, message: "must be exactly 4 digits" }, allow_blank: true, if: :admin?
  validate :admin_requires_a_pin
  before_validation :clear_pin_unless_admin

  def initial
    name.to_s.strip[0]&.upcase || "?"
  end

  def admin?
    role == "admin"
  end

  def requires_pin?
    admin?
  end

  # bcrypt compares in constant time, so this keeps the timing property the
  # plaintext secure_compare gave, and adds resistance to offline guessing if a
  # database copy leaks. The deliberate slowness is affordable because PIN entry
  # is rate-limited (see PinThrottling).
  def verify_pin(input)
    given = input.to_s.strip
    return false if pin_digest.blank? || given.empty?

    authenticate_pin(given).present?
  end

  private

  def admin_requires_a_pin
    return unless admin?
    return if pin_digest.present?

    errors.add(:pin, "can't be blank")
  end

  def clear_pin_unless_admin
    self.pin = nil unless admin?
  end
end
