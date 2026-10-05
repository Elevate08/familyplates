# frozen_string_literal: true

require "test_helper"

module PlatformAdmin
  class BillingOwnerBackfillTest < ActiveSupport::TestCase
    setup do
      @operator = PlatformAdminAccount.create!(
        email: "operator@example.com", password: "correct horse battery staple", role: "billing"
      )
      @household = households(:one)
      @organizer = family_members(:one)
      @creator = User.create!(email: "creator@household.test")
      @organizer.update!(user: @creator)
      @member_user = User.create!(email: "member@household.test")
      family_members(:two).update!(user: @member_user)
    end

    test "a household member named by explicit evidence becomes the billing owner" do
      result = backfill([ row(@creator, "Signup log 2026-03-01: creator@household.test opened this household") ])

      assert_equal({ @household.id => :assigned }, result)
      assert_equal @creator, @household.reload.billing_owner
      event = PlatformAuditEvent.find_by!(action: "household.billing_owner_backfilled", target_id: @household.id)
      assert_equal @operator, event.platform_admin
      assert_equal @creator.id, event.metadata["user_id"]
    end

    test "agreeing evidence from several sources still assigns the one user" do
      result = backfill([
        row(@creator, "Signup log names creator@household.test"),
        row(@creator, "Stripe export: card holder creator@household.test")
      ])

      assert_equal :assigned, result[@household.id]
      assert_equal @creator, @household.reload.billing_owner
    end

    test "a row with no evidence assigns nothing" do
      [ nil, "", "   " ].each do |evidence|
        assert_equal :no_evidence, backfill([ row(@creator, evidence) ])[@household.id]
      end

      assert_nil @household.reload.billing_owner_user_id
    end

    test "no rows leave every household without an owner, whoever its first admin is" do
      assert_equal({}, backfill([]))

      assert_nil @household.reload.billing_owner_user_id
      assert_nil households(:two).reload.billing_owner_user_id
      assert_equal @creator.email, @household.email, "precondition: the household email is the first admin's"
    end

    test "evidence naming different users is ambiguous and assigns no one" do
      result = backfill([
        row(@creator, "Signup log names creator@household.test"),
        row(@member_user, "Stripe export: card holder member@household.test")
      ])

      assert_equal :ambiguous, result[@household.id]
      assert_nil @household.reload.billing_owner_user_id
    end

    test "evidence for a user outside the household assigns nothing" do
      outsider = User.create!(email: "outsider@example.com")

      assert_equal :not_member, backfill([ row(outsider, "Stripe export: card holder outsider@example.com") ])[@household.id]
      assert_nil @household.reload.billing_owner_user_id
    end

    test "evidence for an address with no account assigns nothing" do
      result = backfill([ { household_id: @household.id, user_email: "nobody@example.com", evidence: "Signup log" } ])

      assert_equal :unknown_user, result[@household.id]
      assert_nil @household.reload.billing_owner_user_id
    end

    test "an unknown household is reported, not created" do
      result = backfill([ { household_id: "missing", user_email: @creator.email, evidence: "Signup log" } ])

      assert_equal({ "missing" => :unknown_household }, result)
    end

    test "a household that already has an owner keeps it" do
      @household.update!(billing_owner: @member_user)

      assert_equal :already_owned, backfill([ row(@creator, "Signup log names creator@household.test") ])[@household.id]
      assert_equal @member_user, @household.reload.billing_owner
    end

    test "a support operator cannot backfill" do
      support = PlatformAdminAccount.create!(email: "support@example.com", password: "correct horse battery staple", role: "support")

      assert_raises(BillingOwnerBackfill::Error) do
        BillingOwnerBackfill.new(operator: support).run([ row(@creator, "Signup log") ])
      end
      assert_raises(BillingOwnerBackfill::Error) do
        BillingOwnerBackfill.new(operator: nil).run([ row(@creator, "Signup log") ])
      end
      assert_nil @household.reload.billing_owner_user_id
    end

    private

    def backfill(rows)
      BillingOwnerBackfill.new(operator: @operator).run(rows)
    end

    def row(user, evidence)
      { household_id: @household.id, user_email: user.email, evidence: evidence }
    end
  end
end
