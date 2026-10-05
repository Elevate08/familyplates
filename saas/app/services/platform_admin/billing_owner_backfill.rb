# frozen_string_literal: true

module PlatformAdmin
  # Assigns billing owners to households created before there was one, from
  # evidence the operator supplies: who created or pays for each household,
  # taken from a record outside this database (a signup log, a reconciled
  # Stripe export). Nothing is inferred. A household with no row, the first
  # admin, a member, or the household's email address is never a basis for
  # ownership, so those households stay without an owner until recovery.
  #
  # rows: [{ household_id:, user_email:, evidence: }, ...]. Returns
  # { household_id => outcome }; only :assigned changed anything.
  class BillingOwnerBackfill
    class Error < StandardError; end

    def initialize(operator:)
      @operator = operator
    end

    def run(rows)
      raise Error, "Only an owner or billing operator can backfill billing owners." unless @operator&.can_manage_billing?

      rows.map(&:symbolize_keys).group_by { |row| row[:household_id].to_s }.to_h do |household_id, household_rows|
        [ household_id, backfill(household_id, household_rows) ]
      end
    end

    private

    def backfill(household_id, rows)
      household = Household.find_by(id: household_id)
      return :unknown_household unless household
      return :already_owned if household.billing_owner_user_id.present?
      return :no_evidence if rows.any? { |row| row[:evidence].to_s.strip.empty? }

      emails = rows.map { |row| row[:user_email].to_s.strip.downcase }.uniq
      # Two sources naming different people is a dispute, not evidence.
      return :ambiguous unless emails.one?

      user = User.find_by(email: emails.first)
      return :unknown_user unless user
      return :not_member unless user.family_members.exists?(household: household)

      household.transaction do
        household.update!(billing_owner: user)
        PlatformAuditEvent.record!(
          action: "household.billing_owner_backfilled",
          actor: @operator,
          target: household,
          metadata: { user_id: user.id, evidence: rows.map { |row| row[:evidence].to_s.strip }.uniq }
        )
      end
      :assigned
    end
  end
end
