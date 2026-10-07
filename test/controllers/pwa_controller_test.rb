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

    # Offline: every kept page comes back
    assert_equal "network /recipes/12", result["offlineCachedRecipe"]
    assert_equal "network /meal_plans/4", result["offlinePlan"]
    result["offlineFallbacks"].each do |path, reply|
      assert_notice_page reply["body"], path
      assert_equal 503, reply["status"], path
    end

    # Only a navigation gets the notice page or the plan; other fetches get the network error
    result["offlineNonNavigation"].each do |path, reply|
      assert_equal true, reply["response"], "#{path}: a non-navigation fetch must not get a page"
      assert reply["error"].present? || !reply["intercepted"], "#{path}: expected the network error, or no interception"
    end

    assert_not_includes %w[familyplates-v1 familyplates-v2 familyplates-v3 familyplates-v4], cache_name, "CACHE_NAME must be bumped"
    assert_equal [ cache_name ], result["cachesAfterActivate"]
  end

  # A Turbo visit to "/" follows the redirect to the current plan; the plan is kept under its own address,
  # with a time stamp, and the worker adds no request of its own.
  test "service worker keeps a plan reached through a redirect under its own address" do
    result = run_service_worker

    assert_equal [ "/meal_plans/4" ], result["turboHomeCached"]
    assert_equal [ "/meal_plans/4" ], result["turboIndexCached"]
    assert_equal [ "/" ], result["turboNetworkCalls"]
    assert result["turboStamp"].present?, "a kept page carries the time it was kept"
  end

  # The browser follows a navigation's redirect itself, so the worker sees only an opaque redirect. A second
  # fetch from the worker would race the browser's own (and run the plan page twice), so it makes none.
  test "service worker makes no request of its own for a navigation that redirects" do
    result = run_service_worker

    assert_equal 0, result["navigateRedirectStatus"]
    assert_empty result["navigateRedirectCached"]
    assert_equal %w[/ /meal_plans], result["navigateRedirectCalls"]
    assert_equal [ "/meal_plans/4" ], result["navigateFollowedCached"]
  end

  test "service worker shows the most recently kept plan for / and /meal_plans offline" do
    result = run_service_worker

    assert_equal "network /meal_plans/4", result["latestPlanHome"]
    assert_equal "network /meal_plans/4", result["latestPlanIndex"], "a month view (query string) is never the plan shown"
    assert_notice_page result["latestPlanQuery"], "/meal_plans?view=month has no copy"
    assert_equal "network /meal_plans/9", result["latestPlanAfterRevisit"]
    assert_nil result["latestPlanTurbo"]["response"], "only a navigation is answered with the plan"
    assert result["latestPlanTurbo"]["error"].present?

    assert_notice_page result["noPlanHome"]["body"], "/ with no plan kept"
    assert_equal 503, result["noPlanHome"]["status"]
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

  test "service worker drops the kept copy of a page or file the server says is gone" do
    result = run_service_worker

    assert_equal 404, result["goneStatus"], "the person still sees the server's answer"
    assert_equal [ "/recipes/13" ], result["goneKept"], "404 and 410 delete the copy; a 500 keeps it"
  end

  test "service worker saves the grocery list and recipes at install, only from a plain 200" do
    result = run_service_worker
    icons = %w[/favicon.ico /icon.png /icon.svg]

    assert_equal (icons + %w[/grocery_list /recipes]).sort, result["installSignedIn"]
    assert_equal icons, result["installSignedOut"], "a redirect to sign-in is not kept"
    assert_equal icons, result["installFailing"], "an error page is not kept"
  end

  private

  # The harness takes about a second, so it runs once for the class and every test reads the result.
  class << self
    attr_accessor :harness_run
  end

  def run_service_worker
    skip "node is not available" unless node_available?

    self.class.harness_run ||= begin
      get pwa_service_worker_url(format: :js)
      source = response.body
      out, err, status = Open3.capture3("node", Rails.root.join("test/support/service_worker_harness.js").to_s, stdin_data: source)
      assert status.success?, "harness failed: #{err}"
      { source: source, result: JSON.parse(out) }
    end
    self.class.harness_run[:result]
  end

  def cache_name
    self.class.harness_run[:source][/CACHE_NAME = "([^"]+)"/, 1]
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
