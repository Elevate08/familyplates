require "test_helper"

# SA-02. Active Storage's direct-upload endpoint has no sign-in check, so anyone
# could create a blob and PUT bytes into storage/ (the same volume as the SQLite
# databases in production). The app never uses direct uploads: recipe images
# arrive through the recipe form. The endpoint, and the disk endpoint that
# accepts the bytes, are refused for everyone.
class ActiveStorageDirectUploadsTest < ActionDispatch::IntegrationTest
  test "an anonymous client cannot create a direct upload" do
    assert_no_difference("ActiveStorage::Blob.count") { post_direct_upload }

    assert_response :not_found
  end

  test "a signed-in organizer cannot create a direct upload" do
    sign_in_as(family_members(:one))

    assert_no_difference("ActiveStorage::Blob.count") { post_direct_upload }

    assert_response :not_found
  end

  # Without a CSRF token the request would be a 422 if forgery protection ran
  # first, so a 404 shows the guard runs before it.
  test "the direct-upload guard runs before forgery protection" do
    forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    assert_no_difference("ActiveStorage::Blob.count") { post_direct_upload }

    assert_response :not_found
  ensure
    ActionController::Base.allow_forgery_protection = forgery_protection
  end

  test "bytes cannot be uploaded even with a valid direct-upload token" do
    ActiveStorage::Current.url_options = { host: "www.example.com" }
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "pixel.png",
      byte_size: pixel.bytesize,
      checksum: OpenSSL::Digest::MD5.base64digest(pixel),
      content_type: "image/png"
    )

    put blob.service_url_for_direct_upload, params: pixel, headers: blob.service_headers_for_direct_upload

    assert_response :not_found
    assert_not blob.service.exist?(blob.key), "the refused upload still wrote to storage"
  end

  private

  def pixel
    @pixel ||= file_fixture("pixel.png").binread
  end

  def post_direct_upload
    post rails_direct_uploads_path,
      params: {
        blob: {
          filename: "evil.png",
          byte_size: pixel.bytesize,
          checksum: OpenSSL::Digest::MD5.base64digest(pixel),
          content_type: "image/png"
        }
      },
      as: :json
  end
end
