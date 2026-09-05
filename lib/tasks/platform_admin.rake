namespace :platform_admin do
  desc "Create a dedicated platform operator account (EMAIL=... PASSWORD=...)"
  task create: :environment do
    email = ENV.fetch("EMAIL").strip.downcase
    password = ENV.fetch("PASSWORD")
    admin = PlatformAdminAccount.create!(email: email, password: password, role: ENV.fetch("ROLE", "owner"))

    puts "Created #{admin.email} (#{admin.role})."
    puts "Add this TOTP provisioning URI to your authenticator now:"
    puts PlatformAdminAccount::Totp.provisioning_uri(admin.otp_secret, email: admin.email)
  end
end
