require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "initializes with default meal schedule times" do
    household = Household.create!(name: "Test Family")
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, household.id)
    assert_match(/\A[A-Z0-9]{4}(?:-[A-Z0-9]{4}){2}\z/, household.join_code)
    assert_equal "08:00", household.breakfast_time
    assert_equal "12:30", household.lunch_time
    assert_equal "18:00", household.dinner_time
    assert_equal false, household.google_calendar_enabled
  end

  test "validates name presence" do
    household = Household.new(name: "")
    assert_not household.valid?
    assert_includes household.errors[:name], "can't be blank"
  end

  test "assigns a unique join code" do
    first = Household.create!(name: "First Family")
    second = Household.create!(name: "Second Family")

    assert_not_equal first.join_code, second.join_code
  end

  test "resolves users through family members" do
    household = households(:one)
    user = User.create!(email: "parent@example.com")
    family_members(:one).update!(user: user)

    assert_includes household.users, user
  end

  test "resets join code to a new unique code" do
    household = households(:one)
    old_code = household.join_code

    household.reset_join_code!

    assert_not_equal old_code, household.join_code
    assert_match(/\A[A-Z0-9]{4}(?:-[A-Z0-9]{4}){2}\z/, household.join_code)
  end

  test "automatically generates a calendar feed token on create" do
    household = Household.create!(name: "Feed Test Family")

    assert household.calendar_feed_token.present?
    assert_kind_of String, household.calendar_feed_token
    assert household.calendar_feed_token.length >= 20
  end

  test "assigns unique calendar feed tokens to different households" do
    first = Household.create!(name: "Alpha Family")
    second = Household.create!(name: "Beta Family")

    assert_not_equal first.calendar_feed_token, second.calendar_feed_token
  end

  test "regenerates calendar feed token" do
    household = households(:one)
    original_token = household.calendar_feed_token

    household.regenerate_calendar_feed_token

    assert_not_equal original_token, household.calendar_feed_token
    assert household.calendar_feed_token.present?
  end
end
