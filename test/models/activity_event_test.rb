require "test_helper"

class ActivityEventTest < ActiveSupport::TestCase
  test "records a meaningful event with household actor and target" do
    household = households(:one)
    actor = family_members(:one)
    recipe = recipes(:one)

    event = ActivityEvent.track!(
      household: household,
      event_type: "recipe.created",
      actor: actor,
      target: recipe,
      source: "web"
    )

    assert_equal household, event.household
    assert_equal actor, event.actor
    assert_equal "Recipe", event.target_type
    assert_equal recipe.id.to_s, event.target_id
    assert_equal "recipe.created", event.event_type
    assert_equal "Dad created recipe #{recipe.title}", event.human_description
  end

  test "does not require an actor for system events" do
    event = ActivityEvent.track!(
      household: households(:one),
      event_type: "calendar.synced",
      source: "calendar"
    )

    assert_nil event.actor
    assert_equal "FamilyPlates synced the calendar", event.human_description
  end

  test "rejects an event without a household or event type" do
    event = ActivityEvent.new

    assert_not event.valid?
    assert_includes event.errors[:household], "must exist"
    assert_includes event.errors[:event_type], "can't be blank"
  end
end
