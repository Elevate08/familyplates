require "application_system_test_case"

# Three controllers revealed a panel and then focused its input from a
# setTimeout. A deferred focus outlives the click that scheduled it: toggle
# twice quickly and the stale callback lands after the panel has closed,
# dragging the caret somewhere the reader is no longer looking. The same shape
# corrupted typing in the ingredient form.
#
# Focusing an unhidden element synchronously is the fix, but only a browser can
# say whether the element is focusable the instant its class changes - hence
# these run in one.
class FocusTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @household = households(:one)
    sign_in_as(@admin)
  end

  test "the pantry icon picker puts the caret in its search box" do
    visit pantry_items_path

    find("button[data-action*='pantry-item-form#togglePicker']").click

    assert_focused "#pantry_icon_search"
  end

  test "opening the icon picker does not yank focus back out of a field" do
    visit pantry_items_path
    assert_selector "#pantry_item_name", wait: 5

    # Both steps in one JS turn, so the second happens well inside the 50ms a
    # deferred focus would have waited. This is the case that actually bites:
    # the picker stays open, the reader has moved to another field, and the
    # timer drags the caret back. Focus on a hidden element is a no-op, so a
    # picker that gets closed again is never the problem.
    page.execute_script(<<~JS)
      document.querySelector("button[data-action*='pantry-item-form#togglePicker']").click()
      document.querySelector("#pantry_item_name").focus()
    JS

    assert_stays_focused "#pantry_item_name"
  end

  test "the bulk tag modal puts the caret in the tag box" do
    visit recipes_path

    first("input[data-bulk-select-target='checkbox']").click
    find("button[data-action*='bulk-select#openTagsModal']").click

    # This never worked before: the controller focused a hidden field.
    assert_focused "#bulk_tag_search"
  end

  test "the mobile filter dropdown puts the caret in its search box" do
    # The dropdown is sm:hidden, so it only exists at a phone width.
    resize_to(390, 800)
    visit recipes_path

    # Several dropdowns share the page - the profile menu in the header is one -
    # and only the filter dropdown has a search box, so pick it by that.
    container = all("[data-controller='dropdown']", visible: :all).find do |el|
      el.has_css?("[data-dropdown-target='searchInput']", visible: :all)
    end
    assert container, "precondition: a dropdown with a search box is on the page"

    within(container) { find("[data-action*='dropdown#toggle']").click }

    assert_focused "[data-dropdown-target='searchInput']"
  end

  private

  def resize_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  # Polls, so a controller that still defers focus passes too - the point is to
  # prove the synchronous version lands, not to fail the old one on timing.
  def assert_focused(selector)
    assert focused_matches?(selector, until_true: true),
      "expected focus on #{selector}, but it was on #{active_element_description}"
  end

  # Waits out any pending timer, then requires focus to still be where it was
  # put. A deferred focus fires inside this window and moves it.
  def assert_stays_focused(selector)
    sleep 0.3
    assert focused_matches?(selector),
      "focus was pulled off #{selector} to #{active_element_description} - a stale deferred focus"
  end

  def focused_matches?(selector, until_true: false)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time

    loop do
      matched = page.evaluate_script(
        "!!(document.activeElement && document.activeElement.matches(#{selector.to_json}))"
      )
      return true if matched
      return false unless until_true
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  def active_element_description
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.activeElement
        if (!el) return "nothing"
        return el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
          (el.type ? "[type=" + el.type + "]" : "")
      })()
    JS
  end
end
