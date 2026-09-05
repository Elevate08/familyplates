# frozen_string_literal: true

namespace :auth do
  desc "Reset an operator password without email (CLI-only recovery)"
  task :reset_password, %i[email password] => :environment do |_t, args|
    email = (args[:email].presence || ENV["EMAIL"].presence).to_s.strip.downcase

    if email.blank?
      print "Enter user email: "
      email = $stdin.gets.to_s.strip.downcase
    end

    if email.blank?
      abort "Error: Email cannot be blank."
    end

    user = User.find_by(email: email)
    unless user
      abort "Error: User '#{email}' not found."
    end

    password = (args[:password].presence || ENV["PASSWORD"].presence).to_s

    if password.blank?
      print "Enter new password: "
      password = $stdin.gets.to_s.chomp
    end

    if password.blank?
      abort "Error: Password cannot be blank."
    end

    if password.length < 8
      abort "Error: Password must be at least 8 characters long."
    end

    user.password = password
    user.save!

    puts "✓ Password successfully updated for #{user.email}."
  end
end
