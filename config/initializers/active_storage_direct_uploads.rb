# Active Storage ships two endpoints that let anyone write files to storage/:
# POST /rails/active_storage/direct_uploads (no sign-in check) mints an upload
# token, and PUT /rails/active_storage/disk/:encoded_token accepts the bytes for
# any valid token. The app never uses direct uploads (recipe images go through the
# recipe form), so both controller actions refuse every request, whatever route
# reaches them. That also closes tokens minted before this was deployed or with a
# leaked key. Blob and image serving, including DiskController#show, are untouched.
# Each callback is a named method, so running this again on a reload replaces it
# rather than adding another.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    before_action :refuse_direct_upload, prepend: true

    private

    def refuse_direct_upload
      head :not_found
    end
  end

  ActiveStorage::DiskController.class_eval do
    before_action :refuse_disk_upload, only: :update, prepend: true

    private

    def refuse_disk_upload
      head :not_found
    end
  end
end
