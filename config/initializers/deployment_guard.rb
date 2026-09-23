# frozen_string_literal: true

# A public deploy names its hostname and, when it sends mail, its SMTP server.
# Both are checked here so a hosted instance never boots half-configured.
# A LAN appliance leaves APP_HOST and SMTP unset and starts as before.
if Rails.env.production?
  if (host = FamilyPlates.public_host)
    FamilyPlates.apply_public_host!(host)
  end

  problems = []
  if FamilyPlates.hosted_host_missing?
    problems << <<~MESSAGE.squish
      APP_HOST is not set. Hosted mode will not start without the public hostname.
      It locks the Host header and it is the host used in email.
      Example: APP_HOST=plates.example.com
    MESSAGE
  end

  begin
    FamilyPlates::OutboundEmail.validate!
  rescue FamilyPlates::OutboundEmailNotConfiguredError => error
    problems << error.message
  end

  if problems.any?
    abort <<~MESSAGE
      FATAL: FamilyPlates will not start.

      #{problems.join("\n\n")}
    MESSAGE
  end
end
