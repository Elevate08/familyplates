require "net/smtp"

class ApplicationMailer < ActionMailer::Base
  # Raised before any message data can have reached the mail server: the
  # connection or login failed. Any other delivery error may follow the
  # server accepting the message, so it is never retried automatically.
  NOT_SENT_ERRORS = [
    Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError,
    Net::OpenTimeout, Net::SMTPAuthenticationError
  ].freeze

  default from: -> { ENV.fetch("MAILER_DEFAULT_FROM", "noreply@familyplates.app") }
  layout "mailer"
end
