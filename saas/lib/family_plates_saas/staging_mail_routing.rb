# frozen_string_literal: true

module FamilyPlatesSaas
  # Staging sends real mail through its own SMTP account, and a tester can sign
  # up a household with anyone's address. Mail goes only to the allowlist
  # (STAGING_MAIL_ALLOWLIST: comma-separated addresses, or @domain for a whole
  # domain); every other recipient is replaced by the sink (STAGING_MAIL_SINK).
  # With no sink, mail with no allowed recipient is not sent at all.
  class StagingMailRouting
    ORIGINAL_RECIPIENTS_HEADER = "X-FamilyPlates-Original-Recipients"

    def initialize(allowlist:, sink:)
      @allowed = allowlist.to_s.split(",").map { |entry| entry.strip.downcase }.reject(&:empty?)
      @sink = sink.to_s.strip.presence
    end

    def delivering_email(message)
      recipients = [ message.to, message.cc, message.bcc ].flat_map { |list| Array(list) }.uniq
      allowed, held = recipients.partition { |address| allowed?(address) }

      delivered = allowed
      delivered += [ @sink ] if held.any? && @sink
      if delivered.empty?
        message.perform_deliveries = false
        return
      end

      message.header[ORIGINAL_RECIPIENTS_HEADER] = held.join(", ") if held.any?
      message.to = delivered.uniq
      message.cc = nil
      message.bcc = nil
    end

    private

    def allowed?(address)
      address = address.to_s.downcase
      @allowed.any? { |entry| entry.start_with?("@") ? address.end_with?(entry) : address == entry }
    end
  end
end
