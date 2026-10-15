# frozen_string_literal: true

require "test_helper"

class HouseholdBillingOwnerTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @owner = User.create!(email: "owner@household.test")
    @household.update!(billing_owner: @owner)
  end

  test "deleting the owner leaves the household without one" do
    @owner.destroy!

    assert Household.exists?(@household.id)
    assert_nil @household.reload.billing_owner_user_id
  end

  test "the database nullifies the owner even when the user row is deleted directly" do
    User.where(id: @owner.id).delete_all

    assert_nil @household.reload.billing_owner_user_id
  end

  test "deleting the household keeps the user" do
    @household.destroy!

    assert User.exists?(@owner.id)
  end

  test "billing_owner? is true only for the owning user" do
    assert @household.billing_owner?(@owner)
    assert_not @household.billing_owner?(User.create!(email: "someone@household.test"))
    assert_not @household.billing_owner?(nil)

    @household.update!(billing_owner: nil)
    assert_not @household.billing_owner?(@owner)
  end
end
