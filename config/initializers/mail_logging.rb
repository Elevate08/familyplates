# Rails logs every delivered email in full at debug level. FamilyPlates emails
# carry live sign-in and verification codes, so RAILS_LOG_LEVEL=debug would
# write working credentials to the log. Keep the one-line delivery record and
# drop the message itself.
#
# Development keeps the full message: with no SMTP there, the log is where a
# developer reads the code to sign in, and those codes open nothing real.
module OmitMailBodyFromLog
  def deliver(event)
    info do
      if (exception = event.payload[:exception_object])
        "Failed delivery of mail #{event.payload[:message_id]} error_class=#{exception.class} error_message=#{exception.message.inspect}"
      elsif event.payload[:perform_deliveries]
        "Delivered mail #{event.payload[:message_id]} (#{event.duration.round(1)}ms)"
      else
        "Skipped delivery of mail #{event.payload[:message_id]} as `perform_deliveries` is false"
      end
    end
  end
end

unless Rails.env.development?
  ActiveSupport.on_load(:action_mailer) do
    ActionMailer::LogSubscriber.prepend(OmitMailBodyFromLog)
  end
end
