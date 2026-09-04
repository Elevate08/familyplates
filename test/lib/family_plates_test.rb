require "test_helper"

class FamilyPlatesTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "defaults to appliance mode and unrequired login" do
    assert_equal "appliance", FamilyPlates.config.mode
    assert FamilyPlates.config.appliance?
    assert_not FamilyPlates.config.hosted?
    assert_equal false, FamilyPlates.config.require_login
  end

  test "prevent enabling REQUIRE_LOGIN when no admin profile has a password" do
    household = households(:one)
    household.family_members.update_all(user_id: nil)

    assert_not household.can_require_login?
    assert_raises(FamilyPlates::AdminPasswordRequiredError) do
      FamilyPlates.config.require_login = true
    end
  end

  test "allows enabling REQUIRE_LOGIN when at least one admin has a password" do
    household = households(:one)
    admin_member = household.family_members.find_by!(role: "admin")
    admin_user = User.create!(email: "admin@example.com", password: "admin-password-123")
    admin_member.update!(user: admin_user)

    assert household.can_require_login?
    assert_nothing_raised do
      FamilyPlates.config.require_login = true
    end
    assert_equal true, FamilyPlates.config.require_login
  end

  test "outbound email validation fails fast in hosted mode without smtp settings" do
    FamilyPlates.config.mode = "hosted"

    original_method = ActionMailer::Base.delivery_method
    original_settings = ActionMailer::Base.smtp_settings
    begin
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {}
      assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: ActiveSupport::StringInquirer.new("production"))
      end
    ensure
      ActionMailer::Base.delivery_method = original_method
      ActionMailer::Base.smtp_settings = original_settings
    end
  end
end
