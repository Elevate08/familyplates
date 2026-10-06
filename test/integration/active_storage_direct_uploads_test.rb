require "test_helper"

# SA-02. Active Storage draws a direct-upload endpoint by default, and its
# controller has no sign-in check, so anyone could create a blob and PUT bytes
# into storage/ (the same volume as the SQLite databases in production). The
# app never uses direct uploads: recipe images arrive through the recipe form.
# The endpoint is refused for everyone, while serving recipe images still works.
class ActiveStorageDirectUploadsTest < ActionDispatch::IntegrationTest
  PNG = "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82".b

  setup { @forgery_protection = ActionController::Base.allow_forgery_protection }
  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection }

  test "an anonymous client with a valid CSRF token cannot create a direct upload" do
    enforce_forgery_protection
    token = csrf_token_from_sign_in_page

    assert_no_difference("ActiveStorage::Blob.count") do
      post_direct_upload(token)
    end

    assert_response :not_found
  end

  test "a signed-in organizer cannot create a direct upload" do
    sign_in_as(family_members(:one))
    enforce_forgery_protection
    token = csrf_token_from_sign_in_page

    assert_no_difference("ActiveStorage::Blob.count") do
      post_direct_upload(token)
    end

    assert_response :not_found
  end

  test "the disk upload endpoint refuses a request without a direct-upload token" do
    enforce_forgery_protection
    token = csrf_token_from_sign_in_page

    assert_no_difference("ActiveStorage::Blob.count") do
      put "/rails/active_storage/disk/not-a-signed-token",
        params: PNG,
        headers: { "X-CSRF-Token" => token, "Content-Type" => "image/png" }
    end

    assert_response :not_found
  end

  test "a recipe image uploaded through the recipe form attaches and is served" do
    sign_in_as(family_members(:one))
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", true, original_filename: "test.png")

    assert_difference([ "Recipe.count", "ActiveStorage::Blob.count" ], 1) do
      post recipes_url, params: { recipe: { title: "Blueberry French Toast", meal_types: "breakfast", image: file } }
    end

    recipe = Recipe.last
    assert recipe.image.attached?

    get recipe.display_image_url
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal PNG, response.body.b
  end

  private

  # Forgery protection is off in the test environment. Turn it on (after signing
  # in, which posts without a token) so a refusal here cannot be a CSRF failure
  # in disguise: every request below carries a valid token.
  def enforce_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  def csrf_token_from_sign_in_page
    get new_session_path
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    assert token.present?, "expected the sign-in page to carry a CSRF token"
    token
  end

  def post_direct_upload(token)
    post "/rails/active_storage/direct_uploads",
      params: {
        blob: {
          filename: "evil.png",
          byte_size: PNG.bytesize,
          checksum: OpenSSL::Digest::MD5.base64digest(PNG),
          content_type: "image/png"
        }
      },
      as: :json,
      headers: { "X-CSRF-Token" => token }
  end
end
