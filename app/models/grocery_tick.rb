# A grocery item ticked (or un-ticked) on a household's shopping list, shared by
# every device in the household. A list is an exact date range; item_key is the
# checklist row's stable id (aisle_name_unit, parameterized).
#
# Last change wins: a change is kept only if its changed_at is newer than the
# stored one. changed_at comes from the client's clock, so a time in the future
# is clamped to now (a phone with a wrong clock can't pin an item for good).
class GroceryTick < ApplicationRecord
  ITEM_KEY_FORMAT = /\A[a-z0-9_-]{1,200}\z/

  belongs_to :household
  belongs_to :family_member, optional: true

  validates :item_key, format: { with: ITEM_KEY_FORMAT }
  validates :list_from, :list_to, :changed_at, presence: true
  validates :checked, inclusion: { in: [ true, false ] }
  validate :range_is_a_grocery_range

  scope :for_list, ->(from, to) { where(list_from: from, list_to: to) }

  # { "item_key" => true/false } for the scoped ticks.
  def self.checked_map
    pluck(:item_key, :checked).to_h
  end

  # Applies one change and returns the tick that stands afterwards (the stored
  # one, when it is newer than the incoming change).
  def self.record!(household:, from:, to:, item_key:, checked:, changed_at:, family_member:)
    changed_at = [ changed_at, Time.current ].min
    attempts = 0
    begin
      transaction do
        tick = household.grocery_ticks.find_or_initialize_by(list_from: from, list_to: to, item_key: item_key)
        if tick.new_record? || changed_at > tick.changed_at
          tick.assign_attributes(checked: checked, changed_at: changed_at, family_member: family_member)
          tick.save!
        end
        tick
      end
    rescue ActiveRecord::RecordNotUnique
      # Two devices ticked the same new item at once; the second pass sees the first's row.
      retry if (attempts += 1) < 2
      raise
    end
  end

  private

  def range_is_a_grocery_range
    return if list_from.blank? || list_to.blank?

    if list_to < list_from
      errors.add(:list_to, "can't be before the first day")
    elsif list_to > list_from + (GroceryRange::MAX_DAYS - 1).days
      errors.add(:list_to, "is more than #{GroceryRange::MAX_DAYS} days after the first day")
    end
  end
end
