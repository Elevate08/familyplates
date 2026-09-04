require "test_helper"

class PlatformAdmin::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(
      email: "operator@example.com",
      password: "correct horse battery staple",
      otp_secret: "JBSWY3DPEHPK3PXP"
    )
    @alpha = households(:one)
    @beta = Household.create!(name: "Miller Family")
    @alpha.update!(name: "Alpha Kitchen")
    @beta.update!(name: "Beta Kitchen")
    @alpha.family_members.first.update!(user: User.create!(email: "alpha@example.com"))
    @beta.family_members.create!(name: "Beta Admin", role: "admin", pin: "1234", user: User.create!(email: "beta@example.com"))
    sign_in_platform_admin(@admin)
  end

  test "lists household metadata and counts" do
    get platform_admin_households_path

    assert_response :success
    assert_select "h1", text: /Households/i
    assert_includes response.body, "Alpha Kitchen"
    assert_includes response.body, "Beta Kitchen"
    assert_includes response.body, "Recipes"
  end

  test "searches by household name or customer email" do
    get platform_admin_households_path, params: { search: "beta@example.com" }

    assert_response :success
    assert_includes response.body, "Beta Kitchen"
    assert_not_includes response.body, "Alpha Kitchen"
  end

  test "shows privacy-safe household details" do
    get platform_admin_household_path(@alpha)

    assert_response :success
    assert_select "h1", text: "Alpha Kitchen"
    assert_includes response.body, "Members"
    assert_includes response.body, "Recipes"
    assert_not_includes response.body, @alpha.join_code
  end

  private

  def sign_in_platform_admin(admin)
    post platform_admin_session_path, params: {
      email: admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
    }
  end
end
