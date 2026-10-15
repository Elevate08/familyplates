# frozen_string_literal: true

# Active Storage ships two endpoints that let anyone write files to storage/:
# POST /rails/active_storage/direct_uploads (no sign-in check) mints an upload
# token, and PUT /rails/active_storage/disk/:encoded_token accepts the bytes for
# any valid token. The app never uses direct uploads (recipe images go through the
# recipe form), so every action of DirectUploadsController is refused, and every
# action of DiskController except #show, which serves images, whatever route
# reaches them. Disk tokens expire after service_urls_expire_in (5 minutes);
# refusing the PUT as well is for a leaked secret_key_base and for any future
# token minting.
module RefuseActiveStorageWrites
  extend ActiveSupport::Concern

  included do
    before_action :refuse_active_storage_write, prepend: true
  end

  private

  def refuse_active_storage_write
    head :not_found
  end
end

Rails.application.config.to_prepare do
  [ ActiveStorage::DirectUploadsController, ActiveStorage::DiskController ].each do |controller|
    next if controller.ancestors.include?(RefuseActiveStorageWrites)

    controller.include(RefuseActiveStorageWrites)
    # Serving images stays open.
    controller.skip_before_action :refuse_active_storage_write, only: :show if controller == ActiveStorage::DiskController
  end
end
