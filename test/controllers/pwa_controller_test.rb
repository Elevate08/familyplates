require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "should get manifest" do
    get pwa_manifest_url(format: :json)
    assert_response :success
    assert_includes ["application/json", "application/manifest+json"], response.media_type
    json = JSON.parse(response.body)
    assert_equal "FamilyPlates", json["name"]
    assert_equal "standalone", json["display"]
    assert_equal "#ea580c", json["theme_color"]
  end

  test "should get service worker" do
    get pwa_service_worker_url(format: :js)
    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_includes response.body, "familyplates"
  end
end
