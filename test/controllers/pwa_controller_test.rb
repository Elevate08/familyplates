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
    result = run_service_worker

    assert_equal %w[
      /assets/application-abc123.css /favicon.ico /grocery_list /grocery_list/3 /grocery_list/current /icon.png /icon.svg
      /manifest.json /meal_plans /meal_plans/4 /meal_plans/4/print /recipes /recipes/12 /recipes/12/cook
    ].sort, result["cachedPaths"]

    assert_equal false, result["postIntercepted"]
    assert_equal false, result["crossOriginIntercepted"]
    assert_equal false, result["exportIntercepted"], "non-asset GETs such as exports must go straight to the network"
    assert_empty result["signInRedirectCached"], "a redirect to the sign-in page must never be kept"

    # Offline: every kept page comes back, and "/" (start_url, navbar Planner link) shows the current plan
    assert_equal "network /recipes/12", result["offlineCachedRecipe"]
    assert_equal "network /meal_plans/4", result["offlineHome"], "/ must show the cached current plan offline"
    assert_equal "network /meal_plans/4", result["offlineHomeTurbo"]
    assert_equal "network /meal_plans/4", result["offlinePlanIndex"]
    assert_equal "network /meal_plans/4", result["offlinePlan"]
    result["offlineFallbacks"].each do |path, reply|
      assert_notice_page reply["body"], path
      assert_equal 503, reply["status"], path
    end
    assert_notice_page result["offlineHomeEmpty"]["body"], "/ with nothing kept"
    assert_equal 503, result["offlineHomeEmpty"]["status"]

    # Only a navigation gets the notice page; other fetches get the network error
    result["offlineNonNavigation"].each do |path, reply|
      assert_equal true, reply["response"], "#{path}: a non-navigation fetch must not get a page"
      assert reply["error"].present? || !reply["intercepted"], "#{path}: expected the network error, or no interception"
    end

    current = response.body[/CACHE_NAME = "([^"]+)"/, 1]
    assert_not_includes %w[familyplates-v1 familyplates-v2 familyplates-v3], current, "CACHE_NAME must be bumped"
    assert_equal [ current ], result["cachesAfterActivate"]
  end

  # A Turbo visit follows the redirect from / or /meal_plans to the current plan, so the plan has to be
  # kept from the redirected response, under its own address and as the / and /meal_plans copies.
  test "service worker keeps the current plan reached through a redirect" do
    result = run_service_worker

    assert_equal %w[/ /meal_plans /meal_plans/4], result["turboHomeCached"]
    assert_equal %w[/ /meal_plans /meal_plans/4], result["turboIndexCached"]
    # A navigation leaves the redirect to the browser, so the worker looks the plan up itself
    assert_equal %w[/ /meal_plans /meal_plans/4], result["navigateHomeCached"]
    assert_equal %w[/ /meal_plans /meal_plans/4], result["navigateIndexCached"]
    assert_equal [ "/recipes" ], result["navigateOtherRedirectNetworkCalls"], "only / and /meal_plans need a second look"
  end

  test "service worker writes the / and /meal_plans copies only from the current-week redirect" do
    result = run_service_worker

    assert_equal %w[/meal_plans/9 /meal_plans/9/print], result["otherPlanWrites"].uniq.sort,
                 "another week's plan is kept under its own address only; month views are not kept"
    assert_equal "network /meal_plans/4", result["homeCopyAfterOtherPlans"]
    assert_equal "network /meal_plans/4", result["indexCopyAfterOtherPlans"]
  end

  test "service worker never keeps Turbo Frame responses" do
    result = run_service_worker

    assert_empty result["frameWrites"], "a frame response is a fragment, not a page"
    assert_equal "network /recipes/12", result["frameBody"], "the frame request still gets its answer"
  end

  test "service worker does not keep offline pages that have a query string" do
    assert_empty run_service_worker["queryWrites"]
  end

  test "service worker keeps uploaded recipe photos and serves them offline" do
    result = run_service_worker

    assert_equal %w[
      /rails/active_storage/blobs/proxy/abc/photo.jpg /rails/active_storage/blobs/redirect/abc/photo.jpg
      /rails/active_storage/representations/redirect/abc/def/photo.jpg
    ], result["photoCached"]
    assert_equal "network /rails/active_storage/blobs/redirect/abc/photo.jpg", result["photoOffline"]
    assert_match(/offline/, result["photoNeverSeenOffline"].to_s, "a photo that was never seen gets the network error")
  end

  private

  def run_service_worker
    skip "node is not available" unless node_available?

    get pwa_service_worker_url(format: :js)
    out, err, status = Open3.capture3("node", Rails.root.join("test/support/service_worker_harness.js").to_s, stdin_data: response.body)
    assert status.success?, "harness failed: #{err}"
    JSON.parse(out)
  end

  def assert_notice_page(body, label)
    assert_match(/grocery list/i, body, label)
    assert_match(/recipes/i, body, label)
    assert_match(/meal plan/i, body, label)
    assert_no_match(/network \//, body, "#{label} must not fall back to a cached page")
    assert_not_equal "precached /", body
  end

  def node_available?
    _out, _err, status = Open3.capture3("node", "--version")
    status.success?
  rescue Errno::ENOENT
    false
  end
end
