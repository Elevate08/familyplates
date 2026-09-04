# frozen_string_literal: true

# Configure ActionMailer SMTP settings from environment variables if provided.
if ENV["SMTP_ADDRESS"].present?
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = {
    address: ENV["SMTP_ADDRESS"],
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USER_NAME"].presence || ENV["SMTP_USERNAME"].presence,
    password: ENV["SMTP_PASSWORD"].presence,
    authentication: (ENV["SMTP_AUTHENTICATION"].presence || "plain").to_sym,
    enable_starttls_auto: ENV["SMTP_ENABLE_STARTTLS_AUTO"] != "false"
  }.compact
end
