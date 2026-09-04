# frozen_string_literal: true

# Configure ActionMailer SMTP settings from environment variables if provided.
if ENV["SMTP_ADDRESS"].present? && !Rails.env.test?
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.raise_delivery_errors = true

  settings = {
    address: ENV["SMTP_ADDRESS"],
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USER_NAME"].presence || ENV["SMTP_USERNAME"].presence,
    password: ENV["SMTP_PASSWORD"].presence,
    enable_starttls_auto: ENV["SMTP_ENABLE_STARTTLS_AUTO"] != "false",
    domain: ENV["SMTP_DOMAIN"].presence
  }

  settings[:openssl_verify_mode] = ENV["SMTP_OPENSSL_VERIFY_MODE"] if ENV["SMTP_OPENSSL_VERIFY_MODE"].present?

  auth = ENV["SMTP_AUTHENTICATION"].presence
  if auth && auth.downcase != "none" && settings[:password].present?
    settings[:authentication] = auth.to_sym
  elsif settings[:password].present?
    settings[:authentication] = :plain
  end

  ActionMailer::Base.smtp_settings = settings.compact
end
