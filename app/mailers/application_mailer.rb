class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_DEFAULT_FROM", "noreply@familyplates.app") }
  layout "mailer"
end
