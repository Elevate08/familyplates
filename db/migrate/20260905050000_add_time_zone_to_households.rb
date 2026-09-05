class AddTimeZoneToHouseholds < ActiveRecord::Migration[8.1]
  # Timestamps stay in UTC. This is the household's *interpretation* of them:
  # the zone whose wall clock "dinner at 6pm" and "today" are measured against.
  #
  # Null on purpose rather than defaulting to "UTC": blank means "nobody has
  # said yet", which is what lets the first browser through the door seed it.
  def change
    add_column :households, :time_zone, :string
  end
end
