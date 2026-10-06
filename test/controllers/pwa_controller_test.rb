require "test_helper"
require "open3"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "should get manifest" do
    get pwa_manifest_url(format: :json)
    assert_response :success
    assert_includes [ "application/json", "application/manifest+json" ], response.media_type
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

  # SA-05: the worker may keep only the offline pages and static assets.
  test "service worker allow-lists the offline pages and has no catch-all HTML cache" do
    get pwa_service_worker_url(format: :js)
    body = response.body

    %w[grocery_list recipes meal_plans].each do |area|
      assert_includes body, area, "#{area} should be an offline area"
    end
    assert_no_match(/caches\.match\(\s*["']\/["']\s*\)/, body, "must not fall back to the cached home page")
  end

  test "service worker behaviour: caches only offline pages and assets, falls back to a plain offline page" do
    skip "node is not available" unless node_available?

    get pwa_service_worker_url(format: :js)
    out, err, status = Open3.capture3("node", Rails.root.join("test/support/service_worker_harness.js").to_s, stdin_data: response.body)
    assert status.success?, "harness failed: #{err}"
    result = JSON.parse(out)

    assert_equal %w[
      /assets/application-abc123.css /favicon.ico /grocery_list /grocery_list/3 /grocery_list/current /icon.png /icon.svg
      /manifest.json /meal_plans /meal_plans/4 /meal_plans/4/print /recipes /recipes/12 /recipes/12/cook
    ].sort, result["cachedPaths"]

    assert_equal false, result["postIntercepted"]
    assert_equal false, result["crossOriginIntercepted"]
    assert_equal false, result["exportIntercepted"], "non-asset GETs such as exports must go straight to the network"
    assert_equal false, result["redirectedCached"], "a redirected response must never be kept"

    assert_equal "network /recipes/12", result["offlineCachedRecipe"]
    assert_equal "network /meal_plans/4", result["offlinePlanIndex"], "/meal_plans only redirects, so the plan seen last answers it"
    result["offlineFallbacks"].each do |path, reply|
      assert_match(/grocery list/i, reply["body"], path)
      assert_match(/recipes/i, reply["body"], path)
      assert_match(/meal plan/i, reply["body"], path)
      assert_no_match(/network \//, reply["body"], "#{path} must not fall back to a cached page")
      assert_not_equal "precached /", reply["body"]
    end

    current = response.body[/CACHE_NAME = "([^"]+)"/, 1]
    assert_not_includes %w[familyplates-v1 familyplates-v2], current, "CACHE_NAME must be bumped"
    assert_equal [ current ], result["cachesAfterActivate"]
  end

  private

  def node_available?
    _out, _err, status = Open3.capture3("node", "--version")
    status.success?
  rescue Errno::ENOENT
    false
  end
end
