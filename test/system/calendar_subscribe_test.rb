require "application_system_test_case"

class CalendarSubscribeTest < ApplicationSystemTestCase
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "opens calendar subscription modal and switches tabs on meal planner" do
    sign_in_as(@admin)
    visit meal_plans_path

    assert_button "Sync Calendar", wait: 5
    click_button "Sync Calendar"

    assert_text "Subscribe to Calendar"
    assert_text "Live meal schedule synced to your phone or computer"
    assert_link "Apple Calendar"
    assert_link "Google Calendar"

    # Default is All Household Meals
    assert_text(/Universal Feed URL \(\.ics\)/i)
    assert_field readonly: true, with: /calendars\/feed\/#{@household.calendar_feed_token}/

    # Switch to My Cooking tab
    click_button "👨‍🍳 #{@admin.name}'s Cooking"

    assert_text(/Personalized Feed URL \(\.ics\)/i)
    assert_field readonly: true, with: /calendars\/feed\/#{@household.calendar_feed_token}\/members\/#{@admin.id}/

    # Close modal
    click_button "Done"
  end

  test "admin can view calendar subscription feed and regenerate token in settings" do
    sign_in_as(@admin)
    visit edit_admin_calendar_path

    assert_text "Universal Calendar Subscriptions"
    assert_text "Zero-config live feeds for Apple Calendar, Google Calendar, Outlook, and more"
    assert_field readonly: true, with: /calendars\/feed\/#{@household.calendar_feed_token}/

    old_token = @household.calendar_feed_token

    click_button "Regenerate Feed Link"
    click_button "Confirm"

    assert_text "Calendar subscription feed link has been regenerated!"
    @household.reload
    assert_not_equal old_token, @household.calendar_feed_token
    assert_field readonly: true, with: /calendars\/feed\/#{@household.calendar_feed_token}/
  end
end
