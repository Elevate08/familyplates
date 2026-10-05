# frozen_string_literal: true

require "test_helper"

# Notice of a changed Terms version (TermsNotice): one per person per version,
# never sent twice, never assumed sent, and the change is required of them
# only NOTICE_LEAD_TIME after a recorded submission.
class TermsNoticeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  NEW_VERSION = "2027-01-01"

  setup do
    FamilyPlates.config.mode = "hosted"
    @accepted = User.create!(email: "accepted@notice.test", **accepted_terms)
    @never = User.create!(email: "never@notice.test")
  end

  teardown do
    FamilyPlates.config.reset!
    if TermsNoticeMailer.singleton_class.method_defined?(:changed_terms, false)
      TermsNoticeMailer.singleton_class.remove_method(:changed_terms)
    end
  end

  test "nothing is queued while everyone is on the current version" do
    assert_equal 0, TermsNotice.schedule!
    assert_no_emails { TermsNotice.recover! }
  end

  test "a new version queues one notice per earlier acceptor, however often scheduling runs" do
    with_current_terms_version(NEW_VERSION) do
      assert_equal 1, TermsNotice.schedule!
      assert_equal 0, TermsNotice.schedule!
      notice = TermsNotice.sole
      assert_equal [ @accepted.id, NEW_VERSION, Legal::TERMS_VERSION, "queued" ],
        [ notice.user_id, notice.terms_version, notice.previous_terms_version, notice.state ]
      assert_raises(ActiveRecord::RecordNotUnique) do
        TermsNotice.create!(user_id: @accepted.id, terms_version: NEW_VERSION)
      end
    end
  end

  test "the notice is emailed once, states its date, and starts the 30 days from submission" do
    with_current_terms_version(NEW_VERSION) do
      freeze_time do
        assert_emails(1) { TermsNotice.recover! }
        assert_no_emails { TermsNotice.recover! }

        notice = TermsNotice.sole
        assert_equal "submitted", notice.state
        assert_equal Time.current, notice.submitted_at
        enforced_from = notice.enforcement_at
        assert_equal notice.stated_enforcement_at, enforced_from
        assert_operator enforced_from, :>=, 30.days.from_now

        mail = ActionMailer::Base.deliveries.last
        assert_equal [ @accepted.email ], mail.to
        assert_includes mail.text_part.body.to_s, NEW_VERSION
        assert_includes mail.text_part.body.to_s, enforced_from.utc.to_formatted_s(:long)
        assert_includes mail.text_part.body.to_s, "/terms_acceptance"

        assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION)
        assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: enforced_from - 1.second)
        assert TermsNotice.enforceable?(@accepted, NEW_VERSION, now: enforced_from)
        assert_not TermsAssent.acceptance_required?(@accepted)
        assert TermsAssent.acceptance_required?(@accepted, now: enforced_from)
      end
    end
  end

  test "across a daylight-saving change the notice period follows the household's clock, never ending early" do
    households(:one).update!(time_zone: "America/New_York")
    family_members(:one).update!(user: @accepted)
    submitted = Time.utc(2026, 10, 20, 16) # noon in New York, EDT
    period_end = TermsAssent.notice_period_end(@accepted, submitted)

    # 30 days later is November 19, still noon in New York, now EST: 721 hours.
    assert_equal Time.utc(2026, 11, 19, 17), period_end
    assert_equal "2026-11-19 12:00", period_end.in_time_zone("America/New_York").strftime("%Y-%m-%d %H:%M")
    assert_operator period_end, :>=, submitted + 720.hours

    notice = TermsNotice.create!(user_id: @accepted.id, terms_version: NEW_VERSION, state: "submitted",
      submitted_at: submitted, stated_enforcement_at: submitted + 720.hours)
    assert_equal period_end, notice.enforcement_at, "the later of the stated date and the local 30 days"
    assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: period_end - 1.second)
    assert TermsNotice.enforceable?(@accepted, NEW_VERSION, now: period_end)
  end

  test "a send that may have reached the mail server is held for an operator, never resent" do
    with_current_terms_version(NEW_VERSION) do
      TermsNotice.schedule!
      stub_mailer { raise Net::ReadTimeout }

      TermsNotice.recover!
      notice = TermsNotice.sole
      assert_equal "uncertain", notice.state
      assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: 1.year.from_now), "no proof, no enforcement"
      TermsNotice.recover!
      assert_equal 1, notice.reload.attempts

      travel 1.hour
      freeze_time do
        notice.resolve_uncertain!(delivered: true)
        assert_equal "submitted", notice.reload.state
        assert_equal Time.current, notice.submitted_at, "without the provider's time, the latest it can have been"
        assert_operator notice.submitted_at, :>, notice.claimed_at, "never backdated to the claim"
      end
    end
  end

  # The worker claimed the notice at 12:00, the mail server only took it at
  # 12:10, and the response was lost. The 30 days run from 12:10.
  test "a delayed submission resolved from the provider's log starts the 30 days from the provider's time" do
    claimed = Time.utc(2026, 10, 1, 12)
    actual = claimed + 10.minutes
    notice = TermsNotice.create!(user_id: @accepted.id, terms_version: NEW_VERSION, state: "uncertain", claimed_at: claimed,
      stated_enforcement_at: TermsAssent.notice_period_end(@accepted, claimed))

    travel_to actual + 2.days do
      notice.resolve_uncertain!(delivered: true, submitted_at: actual)
    end

    notice.reload
    assert_equal actual, notice.submitted_at
    assert_equal TermsAssent.notice_period_end(@accepted, actual), notice.enforcement_at
    assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: actual + 30.days - 1.second)
    assert TermsNotice.enforceable?(@accepted, NEW_VERSION, now: actual + 30.days)
  end

  test "an operator resolving without the provider's time records the resolution time, not the claim" do
    claimed = Time.utc(2026, 10, 1, 12)
    actual = claimed + 10.minutes
    notice = TermsNotice.create!(user_id: @accepted.id, terms_version: NEW_VERSION, state: "uncertain", claimed_at: claimed,
      stated_enforcement_at: TermsAssent.notice_period_end(@accepted, claimed))

    # The earliest an operator can be resolving it is once it has actually gone.
    travel_to actual do
      notice.resolve_uncertain!(delivered: true)
    end

    notice.reload
    assert_equal actual, notice.submitted_at
    assert_operator notice.enforcement_at, :>=, TermsAssent.notice_period_end(@accepted, actual)
    assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: claimed + 30.days), "not 30 days from the claim"
    assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: actual + 30.days - 1.second)
    assert TermsNotice.enforceable?(@accepted, NEW_VERSION, now: actual + 30.days)
  end

  test "a provider time before the claim or in the future is refused and the notice stays held" do
    claimed = Time.utc(2026, 10, 1, 12)
    notice = TermsNotice.create!(user_id: @accepted.id, terms_version: NEW_VERSION, state: "uncertain", claimed_at: claimed,
      stated_enforcement_at: TermsAssent.notice_period_end(@accepted, claimed))

    travel_to claimed + 1.hour do
      assert_raises(ArgumentError) { notice.resolve_uncertain!(delivered: true, submitted_at: claimed - 1.second) }
      assert_raises(ArgumentError) { notice.resolve_uncertain!(delivered: true, submitted_at: Time.current + 1.second) }
      assert_raises(ArgumentError) { notice.resolve_uncertain!(delivered: false, submitted_at: claimed) }
    end

    assert_equal "uncertain", notice.reload.state
    assert_nil notice.submitted_at
    assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: claimed + 1.year)
  end

  test "a send acknowledged after a slow provider records when the provider returned, not the claim" do
    with_current_terms_version(NEW_VERSION) do
      TermsNotice.schedule!
      claimed = Time.current.change(usec: 0)
      message = Object.new
      message.define_singleton_method(:message) { true }
      test_case = self
      message.define_singleton_method(:deliver_now) { test_case.travel 10.minutes }
      TermsNoticeMailer.define_singleton_method(:changed_terms) { |*| message }

      assert TermsNotice.sole.deliver!(now: claimed)
      notice = TermsNotice.sole
      assert_operator notice.submitted_at, :>=, claimed + 10.minutes
      assert_operator notice.enforcement_at, :>=, TermsAssent.notice_period_end(@accepted, claimed + 10.minutes)
    end
  end

  test "a send that could not connect is retried, then failed after MAX_ATTEMPTS" do
    with_current_terms_version(NEW_VERSION) do
      TermsNotice.schedule!
      stub_mailer { raise Errno::ECONNREFUSED }

      TermsNotice::MAX_ATTEMPTS.times { TermsNotice.recover! }
      notice = TermsNotice.sole
      assert_equal [ "failed", TermsNotice::MAX_ATTEMPTS ], [ notice.state, notice.attempts ]
      assert_nil notice.stated_enforcement_at
      assert_not TermsNotice.enforceable?(@accepted, NEW_VERSION, now: 1.year.from_now)
    end
  end

  test "a worker lost mid-send leaves the notice uncertain" do
    with_current_terms_version(NEW_VERSION) do
      TermsNotice.schedule!
      TermsNotice.sole.update_columns(state: "sending", claimed_at: 1.hour.ago)

      assert_no_emails { TermsNotice.recover! }
      assert_equal "uncertain", TermsNotice.sole.state
    end
  end

  test "someone who accepts before the notice goes out is not emailed" do
    with_current_terms_version(NEW_VERSION) do
      TermsNotice.schedule!
      TermsAssent.accept!(@accepted, version: NEW_VERSION, context: "reacceptance")

      assert_no_emails { TermsNotice.recover! }
      assert_equal "skipped", TermsNotice.sole.state
    end
  end

  test "a queued notice for a superseded version is skipped" do
    with_current_terms_version(NEW_VERSION) { TermsNotice.schedule! }
    with_current_terms_version("2027-06-01") do
      TermsNotice.recover!
      assert_equal "skipped", TermsNotice.find_by!(terms_version: NEW_VERSION).state
      assert TermsNotice.exists?(terms_version: "2027-06-01", state: "submitted")
    end
  end

  test "the job does nothing on an appliance" do
    FamilyPlates.config.mode = "appliance"
    with_current_terms_version(NEW_VERSION) do
      assert_no_emails { TermsNoticeJob.perform_now }
      assert_empty TermsNotice.all
    end
  end

  private

  def stub_mailer(&failure)
    message = Object.new
    message.define_singleton_method(:message) { true }
    message.define_singleton_method(:deliver_now, &failure)
    TermsNoticeMailer.define_singleton_method(:changed_terms) { |*| message }
  end
end
