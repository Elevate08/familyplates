# frozen_string_literal: true

# Scheduled in config/recurring.yml. Queues and sends notices of a changed
# hosted Terms of Service version. See TermsNotice.recover!.
class TermsNoticeJob < ApplicationJob
  queue_as :default

  def perform
    return unless FamilyPlates.config.hosted?

    TermsNotice.recover!
  end
end
