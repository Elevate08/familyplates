class RecipeRequest < ApplicationRecord
  belongs_to :recipe
  belongs_to :family_member

  scope :active, -> { where(fulfilled_at: nil) }
  scope :fulfilled, -> { where.not(fulfilled_at: nil) }

  validates :week_start_date, presence: true
  validate :only_one_active_request_per_family_member, on: :create

  # Fulfils active requests whose planned date on the calendar has arrived.
  #
  # Called on four hot paths - the meal plan, the recipe index, slot creation and
  # request creation - and used to run `active.find_each` across *every household
  # in the database*, issuing a slot query per request. Now scoped to one
  # household and resolved in a single grouped query plus one write per request
  # that actually qualifies.
  #
  # A request is fulfilled by the earliest slot for its recipe that falls on or
  # before today and no earlier than the request's floor, where the floor is the
  # earlier of week_start_date and created_at.
  def self.auto_fulfill_passed_slots!(household = nil)
    scope = active
    scope = scope.joins(recipe: :household).where(households: { id: household }) if household
    pending = scope.to_a
    return if pending.empty?

    earliest = earliest_slot_dates_for(pending, household)

    pending.each do |request|
      slot_date = earliest[request.recipe_id]
      next if slot_date.nil?
      next if slot_date < floor_for(request)

      request.update_columns(fulfilled_at: slot_date.to_time)
    end
  end

  def self.floor_for(request)
    [ request.week_start_date, request.created_at&.to_date ].compact.min ||
      Date.current.beginning_of_week
  end

  # One query for every recipe under consideration, rather than one per request.
  # The per-request floor is applied in Ruby afterwards - it differs by request,
  # so folding it into SQL would mean a query each again.
  def self.earliest_slot_dates_for(requests, household)
    recipe_ids = requests.map(&:recipe_id).uniq
    floor = requests.map { |r| floor_for(r) }.min

    slots = MealPlanSlot.where(recipe_id: recipe_ids)
                        .where(date: floor..Date.current)
    slots = slots.joins(meal_plan: :household).where(households: { id: household }) if household

    slots.group(:recipe_id).minimum(:date)
  end
  private_class_method :floor_for, :earliest_slot_dates_for

  private

  def only_one_active_request_per_family_member
    if fulfilled_at.nil? && RecipeRequest.where(recipe_id: recipe_id, family_member_id: family_member_id, fulfilled_at: nil).exists?
      errors.add(:recipe_id, "has already been requested and is currently active")
    end
  end
end
