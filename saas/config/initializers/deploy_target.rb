# frozen_string_literal: true

# Production and staging are separate Kamal destinations that both run
# RAILS_ENV=production. See FamilyPlatesSaas::DeployTarget.
if FamilyPlatesSaas::DeployTarget.staging?
  Rails.application.config.middleware.insert_before 0, FamilyPlatesSaas::StagingAccessGate,
    ENV["STAGING_ACCESS_USERNAME"], ENV["STAGING_ACCESS_PASSWORD"]

  ActiveSupport.on_load(:action_mailer) do
    ActionMailer::Base.register_interceptor(
      FamilyPlatesSaas::StagingMailRouting.new(allowlist: ENV["STAGING_MAIL_ALLOWLIST"], sink: ENV["STAGING_MAIL_SINK"])
    )
  end
end

# Not while building an image: assets:precompile boots production with
# SECRET_KEY_BASE_DUMMY set and none of the deploy's settings. Checked whatever
# FAMILYPLATES_MODE says: this file is only loaded by the saas bundle, so a
# mode typo there must not skip the check. The appliance bundle never loads it.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  Rails.application.config.after_initialize do
    FamilyPlatesSaas::DeployTarget.verify!
  rescue FamilyPlatesSaas::DeployTargetError => error
    abort <<~MESSAGE
      FATAL: FamilyPlates will not start as the #{FamilyPlatesSaas::DeployTarget.current} deploy.

      #{error.message}
    MESSAGE
  end
end
