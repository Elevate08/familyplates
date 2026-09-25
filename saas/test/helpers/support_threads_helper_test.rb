require "test_helper"

class SupportThreadsHelperTest < ActionView::TestCase
  test "waiting on support badge includes pulse dot and label" do
    html = support_thread_status_badge("waiting_on_support")

    assert_includes html, "Waiting on support"
    assert_includes html, "bg-amber-50"
    assert_includes html, "animate-pulse"
  end

  test "legacy open status uses the waiting on support badge" do
    html = support_thread_status_badge("open")

    assert_includes html, "Waiting on support"
    assert_includes html, "animate-pulse"
  end

  test "waiting on customer badge has no pulse" do
    html = support_thread_status_badge("waiting_on_customer")

    assert_includes html, "Waiting on customer"
    assert_includes html, "bg-sky-50"
    assert_not_includes html, "animate-pulse"
  end

  test "resolved badge uses emerald styling" do
    html = support_thread_status_badge("resolved")

    assert_includes html, "Resolved"
    assert_includes html, "bg-emerald-50"
  end
end
