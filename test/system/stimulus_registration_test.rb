require "application_system_test_case"

# The ingredient-autofill controller shipped with an orphaned object literal in
# its class body. Every request test passed - they render HTML, they do not run
# it - and `node --check` accepted the file because it does not parse ES
# modules. The feature was simply dead until someone clicked it.
#
# Stimulus knows. It logs "Failed to register controller" and leaves the
# identifier out of its router. This asks it directly, for every controller in
# the repo, so a module that will not load fails here instead of in a browser.
class StimulusRegistrationTest < ApplicationSystemTestCase
  # index.js is the manifest, application.js the setup; neither defines a
  # controller. hello_controller is Rails' generated sample and is registered
  # like any other, so it stays in.
  NOT_CONTROLLERS = %w[index.js application.js].freeze

  def expected_identifiers
    Dir.children(Rails.root.join("app/javascript/controllers"))
       .reject { |f| NOT_CONTROLLERS.include?(f) }
       .grep(/_controller\.js\z/)
       .map { |f| f.delete_suffix("_controller.js").tr("_", "-") }
       .sort
  end

  test "every controller in the repo is registered with Stimulus" do
    sign_in_as(family_members(:one))
    visit root_path
    assert_selector "body", wait: 5

    registered = registered_identifiers
    missing = expected_identifiers - registered

    assert_not_nil registered, "window.Stimulus was never set - the entrypoint itself failed to load"
    assert_empty missing, <<~MESSAGE
      Stimulus refused to register: #{missing.join(", ")}.
      The module threw while loading (a syntax error the browser sees but
      `node --check` does not, or a bad import). Its actions and targets are
      dead on every page. Check the browser console for "Failed to register".
    MESSAGE
  end

  private

  # The loader registers asynchronously, so poll rather than reading the router
  # on the first tick. The window is deliberately wider than Capybara's default:
  # the first page load of a run can be waiting on Propshaft compiling assets,
  # and a slow compile must not read as "the controller is broken". Returns
  # whatever the last poll saw, so the assertion names what is missing rather
  # than reporting a timeout.
  POLL_TIMEOUT = 20

  def registered_identifiers
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + POLL_TIMEOUT
    seen = nil

    loop do
      seen = page.evaluate_script(<<~JS)
        window.Stimulus ? window.Stimulus.router.modules.map((m) => m.identifier) : null
      JS
      return seen.sort if seen && (expected_identifiers - seen).empty?
      return seen&.sort if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end
end
