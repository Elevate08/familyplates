require "test_helper"

# SA-02. Active Storage's direct-upload endpoint has no sign-in check, so anyone
# could create a blob and PUT bytes into storage/ (the same volume as the SQLite
# databases in production). The app never uses direct uploads: recipe images
# arrive through the recipe form. The endpoint is refused for everyone.
class ActiveStorageDirectUploadsTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82".b

  test "an anonymous client cannot create a direct upload" do
    assert_no_difference("ActiveStorage::Blob.count") { post_direct_upload }

    assert_response :not_found
  end

  test "a signed-in organizer cannot create a direct upload" do
    sign_in_as(family_members(:one))

    assert_no_difference("ActiveStorage::Blob.count") { post_direct_upload }

    assert_response :not_found
  end

  private

  def post_direct_upload
    post rails_direct_uploads_path,
      params: {
        blob: {
          filename: "evil.png",
          byte_size: PNG.bytesize,
          checksum: OpenSSL::Digest::MD5.base64digest(PNG),
          content_type: "image/png"
        }
      },
      as: :json
  end
end
