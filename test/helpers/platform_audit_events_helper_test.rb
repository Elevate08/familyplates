require "test_helper"

class PlatformAuditEventsHelperTest < ActionView::TestCase
  test "maps destructive actions to rose classes" do
    classes = platform_audit_action_badge_classes("household.suspended")

    assert_includes classes, "bg-rose-100"
  end

  test "maps successful actions to emerald classes" do
    event = PlatformAuditEvent.new(action: "platform_admin.signed_in")

    assert_includes platform_audit_action_badge_classes(event), "bg-emerald-100"
  end

  test "falls back to slate classes for unknown actions" do
    assert_includes platform_audit_action_badge_classes("household.viewed"), "bg-slate-100"
  end
end
