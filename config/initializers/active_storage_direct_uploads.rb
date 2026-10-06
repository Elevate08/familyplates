# Active Storage ships a direct-upload endpoint (POST /rails/active_storage/direct_uploads)
# with no sign-in check, and it lets anyone write files to storage/. The app never
# uses direct uploads (recipe images go through the recipe form), so the controller
# refuses every request, whatever route reaches it. Blob and image serving are separate
# controllers and are untouched. The callback is a named method, so running this again
# on a reload replaces it rather than adding another.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    before_action :refuse_direct_upload, prepend: true

    private

    def refuse_direct_upload
      head :not_found
    end
  end
end
