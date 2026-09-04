require "test_helper"
require "rake"

class AuthRakeTest < ActiveSupport::TestCase
  setup do
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake.application.rake_require("tasks/auth", [Rails.root.join("lib").to_s])
    Rake::Task.define_task(:environment)
  end

  test "resets user password via rake task" do
    user = User.create!(email: "operator@example.com", password: "old-password-123")

    assert_output(/Password successfully updated/) do
      @rake["auth:reset_password"].invoke(user.email, "brand-new-password-567")
    end

    assert user.reload.authenticate("brand-new-password-567")
    assert_not user.authenticate("old-password-123")
  end
end
