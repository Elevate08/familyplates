# frozen_string_literal: true

module PlatformAdmin
  # Makes a user the household's billing owner after an operator has verified
  # who is asking: the owner's account was deleted, they lost access, or a
  # legacy household never had one. Local only. The Stripe customer, card and
  # subscription stay exactly as they are; nothing here moves a contract or
  # payment method to the new owner. They can cancel or open the portal, and
  # replace the card there themselves.
  class BillingOwnerRecovery
    class Error < StandardError; end

    MIN_EVIDENCE_LENGTH = 20

    def initialize(household, operator:)
      @household = household
      @operator = operator
    end

    # user must hold their own admin profile in the household: someone who
    # merely selected the organizer profile has no user link to it.
    # identity_evidence says how the operator verified this person, for
    # example the support thread and the check made in it.
    def assign!(user:, identity_evidence:, request: nil)
      raise Error, "Only an owner or billing operator can change a billing owner." unless @operator&.can_manage_billing?
      raise Error, "Choose the user to make billing owner." if user.nil?
      raise Error, "#{user.email} is already the billing owner." if @household.billing_owner?(user)
      unless user.family_members.exists?(household: @household, role: "admin")
        raise Error, "#{user.email} does not hold an admin profile in #{@household.name}."
      end

      evidence = identity_evidence.to_s.strip
      if evidence.length < MIN_EVIDENCE_LENGTH
        raise Error, "Describe how this person's identity was verified (at least #{MIN_EVIDENCE_LENGTH} characters)."
      end

      previous_owner_id = @household.billing_owner_user_id
      @household.transaction do
        @household.update!(billing_owner: user)
        PlatformAuditEvent.record!(
          action: "household.billing_owner_recovered",
          actor: @operator,
          target: @household,
          metadata: { user_id: user.id, previous_owner_user_id: previous_owner_id, identity_evidence: evidence },
          request: request
        )
      end
      user
    end
  end
end
