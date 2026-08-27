require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "generates calendar_token on creation" do
    household = Household.create!(name: "Test Family")
    assert_not_nil household.calendar_token
    assert_predicate household.calendar_token, :present?
  end

  test "validates name presence" do
    household = Household.new(name: "")
    assert_not household.valid?
    assert_includes household.errors[:name], "can't be blank"
  end
end
