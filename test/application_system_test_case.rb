require "test_helper"

# Browser-driven tests.
#
# These exist because a whole class of defect passed every other check in this
# suite: a Stimulus controller with an ES-module syntax error that the browser
# refused to register, inline scripts blocked by the Content Security Policy, and
# autofill reading its data from the wrong element. Request tests render HTML;
# they never run it, so every one of those was invisible to them.
#
# The single most valuable thing here is not any individual test - it is
# `assert_no_browser_errors`, which turns the browser's own complaints into
# failures. Any test that loads a page gets that for free.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    # Surfaces CSP violations and JS exceptions in the browser log.
    options.add_argument("--enable-logging")
  end

  # Console noise that is not this application's doing and not worth failing on.
  IGNORED_CONSOLE = [
    /preloaded using link preload but not used/,      # Propshaft emits these in dev and test
    /favicon\.ico/,
    /Autofocus processing was blocked/
  ].freeze

  # A third-party asset that will not load - recipe images point at Unsplash, and
  # a test run should not need the internet. Scoped to "Failed to load resource"
  # from a host that is not the test server, so a CSP refusal ("Refused to load
  # ... violates the following Content Security Policy") still fails, including
  # for an external URL. That distinction is the whole point of this check.
  EXTERNAL_ASSET_FAILURE = %r{\Ahttps?://(?!127\.0\.0\.1|localhost)\S+ - Failed to load resource}

  # FamilyPlates is a single-household appliance, and Authentication falls back
  # to Household.first for an unauthenticated visitor. The fixtures carry a
  # second household whose id happens to sort first, so a browser landing on
  # /select_profile saw that one's empty roster - every member, recipe and plan
  # belongs to the other. Request tests never hit it because signing in sets
  # Current.household from the member.
  #
  # Browser flows start signed out, so they get the production shape: one
  # household. See the note in tasks/plan.md - Household.first is a latent
  # landmine even with the fixtures fixed.
  setup do
    retries = 0
    begin
      Household.where.not(id: households(:one).id).destroy_all
    rescue ActiveRecord::StatementTimeout, SQLite3::BusyException
      retries += 1
      sleep 0.15
      retry if retries < 5
      raise
    end
  end

  teardown do
    assert_no_browser_errors if @assert_console_clean != false
  end

  # Fails on anything the browser logged at SEVERE - uncaught exceptions,
  # refused inline scripts, controllers that failed to register.
  def assert_no_browser_errors
    complaints = browser_errors
    assert_empty complaints, "the browser logged #{complaints.length} error(s):\n#{complaints.join("\n")}"
  end

  def browser_errors
    logs = page.driver.browser.logs.get(:browser)
    logs.select { |entry| entry.level == "SEVERE" }
        .map(&:message)
        .reject { |message| IGNORED_CONSOLE.any? { |pattern| message.match?(pattern) } }
        .reject { |message| message.match?(EXTERNAL_ASSET_FAILURE) }
  rescue StandardError
    [] # a driver without log support should not fail the suite
  end

  # Opt out for a test that deliberately provokes an error.
  def allow_browser_errors!
    @assert_console_clean = false
  end

  # Signs in through the real profile picker, the way a person does.
  def sign_in_as(member, pin: "1234")
    visit select_profile_path
    click_on member.name

    if member.requires_pin?
      fill_in_pin(pin)
    end

    assert_no_selector "form[action='#{set_profile_path(member)}']", wait: 5
  end

  def fill_in_pin(pin)
    find("input[type='password'], input[name='pin']", match: :first).fill_in(with: pin)
    find("input[name='pin']").native.send_keys(:enter)
  end
end
