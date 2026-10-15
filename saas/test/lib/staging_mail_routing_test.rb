require "test_helper"

class StagingMailRoutingTest < ActiveSupport::TestCase
  test "allowlisted recipients get the mail" do
    message = deliver(to: "Tester@Example.com", allowlist: "tester@example.com", sink: "sink@example.net")

    assert message.perform_deliveries
    assert_equal [ "Tester@Example.com" ], message.to
    assert_nil message.header[FamilyPlatesSaas::StagingMailRouting::ORIGINAL_RECIPIENTS_HEADER]
  end

  test "a whole domain can be allowlisted" do
    message = deliver(to: "anyone@team.example", allowlist: "someone@example.com, @team.example", sink: nil)
    assert_equal [ "anyone@team.example" ], message.to
  end

  test "everyone else is replaced by the sink, cc and bcc included" do
    message = deliver(to: "stranger@example.org", cc: "tester@example.com", bcc: "other@example.org",
      allowlist: "tester@example.com", sink: "sink@example.net")

    assert message.perform_deliveries
    assert_equal [ "tester@example.com", "sink@example.net" ], message.to
    assert_empty Array(message.cc)
    assert_empty Array(message.bcc)
    assert_equal "stranger@example.org, other@example.org",
      message.header[FamilyPlatesSaas::StagingMailRouting::ORIGINAL_RECIPIENTS_HEADER].to_s
  end

  test "with no sink, mail for no allowed recipient is not sent" do
    message = deliver(to: "stranger@example.org", allowlist: "tester@example.com", sink: "")
    assert_not message.perform_deliveries
  end

  test "a lookalike domain is not on the allowlist" do
    message = deliver(to: "x@evilteam.example", allowlist: "@team.example", sink: nil)
    assert_not message.perform_deliveries
  end

  test "a sign-in code sent through ActionMailer follows the routing" do
    routing = FamilyPlatesSaas::StagingMailRouting.new(allowlist: "", sink: "sink@example.net")
    ActionMailer::Base.register_interceptor(routing)
    code = Struct.new(:code, :email).new("123456", "stranger@example.org")

    mail = AuthenticationMailer.magic_code(code).deliver_now

    assert_equal [ "sink@example.net" ], mail.to
  ensure
    ActionMailer::Base.unregister_interceptor(routing)
  end

  private

  def deliver(to:, allowlist:, sink:, cc: nil, bcc: nil)
    message = Mail::Message.new(to: to, cc: cc, bcc: bcc, from: "no-reply@dev.familyplates.org", subject: "Code")
    FamilyPlatesSaas::StagingMailRouting.new(allowlist: allowlist, sink: sink).delivering_email(message)
    message
  end
end
