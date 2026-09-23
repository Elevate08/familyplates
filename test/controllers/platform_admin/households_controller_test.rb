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

  teardown do
    FamilyPlates.config.reset!
  end

  test "lists household metadata and lifecycle info" do
    get platform_admin_households_path

    assert_response :success
    assert_select "h1", text: /Households/i
    assert_includes response.body, "Alpha Kitchen"
    assert_includes response.body, "Beta Kitchen"
    assert_includes response.body, "Joined"
    assert_includes response.body, "Promotion"
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
    assert_includes response.body, "Recent household activity"
    assert_not_includes response.body, @alpha.join_code
  end

  test "operator sees every Stripe charge state on that household only" do
    customer = @alpha.set_payment_processor(:fake_processor, allow_fake: true)
    other = @beta.set_payment_processor(:fake_processor, allow_fake: true)

    {
      "ch_paid" => { "status" => "succeeded", "captured" => true },
      "ch_failed" => { "status" => "failed" },
      "ch_pending" => { "status" => "pending" },
      "ch_uncaptured" => { "status" => "succeeded", "captured" => false },
      "ch_partial" => { "status" => "succeeded", "captured" => true },
      "ch_refunded" => { "status" => "succeeded", "refunded" => true },
      "ch_disputed" => { "status" => "succeeded", "disputed" => true, "dispute" => "dp_1" }
    }.each do |processor_id, object|
      refunded = processor_id == "ch_partial" ? 100 : (processor_id == "ch_refunded" ? 400 : 0)
      customer.charges.create!(processor_id: processor_id, amount: 400, amount_refunded: refunded, currency: "usd", object: object)
    end
    other.charges.create!(processor_id: "ch_other_household", amount: 900, currency: "usd", object: { "status" => "succeeded" })

    get platform_admin_household_path(@alpha)

    assert_response :success
    assert_select "[data-charge-state=paid]", text: "Paid"
    assert_select "[data-charge-state=failed]", text: "Failed"
    assert_select "[data-charge-state=pending]", text: "Pending"
    assert_select "[data-charge-state=uncaptured]", text: "Uncaptured"
    assert_select "[data-charge-state=partially_refunded]", text: "Partially refunded"
    assert_select "[data-charge-state=refunded]", text: "Refunded"
    assert_select "[data-charge-state=disputed]", text: "Disputed"
    assert_not_includes response.body, "ch_other_household"

    get platform_admin_household_path(@beta)
    assert_select "[data-charge-state=paid]", text: "Paid", count: 1
    assert_select "[data-charge-state=disputed]", count: 0
  end

  test "operator list shows each household subscription state and stops after one page" do
    FamilyPlates.config.mode = "hosted"
    @alpha.update_columns(created_at: 40.days.ago)
    @beta.update_columns(created_at: 40.days.ago)

    states = {
      "Active Kitchen" => "active",
      "Trial Kitchen" => "trialing",
      "Unpaid Kitchen" => "unpaid",
      "Paused Kitchen" => "paused",
      "Incomplete Kitchen" => "incomplete",
      "Lapsed Kitchen" => "incomplete_expired"
    }
    states.each do |name, status|
      household = Household.create!(name: name)
      household.update_columns(created_at: 40.days.ago)
      household.set_payment_processor :fake_processor, allow_fake: true
      household.payment_processor.subscriptions.create!(
        name: "default",
        processor_id: "sub_#{status}",
        processor_plan: "monthly",
        status: status,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )
    end

    get platform_admin_households_path

    assert_response :success
    assert_select "[data-subscription-status=active]", text: "Active"
    assert_select "[data-subscription-status=trialing]"
    assert_select "[data-subscription-status=unpaid]", text: "Unpaid"
    assert_select "[data-subscription-status=paused]", text: "Paused"
    assert_select "[data-subscription-status=incomplete]", text: "Incomplete"
    assert_select "[data-subscription-status=incomplete_expired]", text: "Incomplete expired"
    assert_includes response.body, "Active Kitchen"
    assert_includes response.body, "Unpaid Kitchen"

    extra = PlatformAdmin::HouseholdsController::PAGE_SIZE
    extra.times { |index| Household.create!(name: "Paged Kitchen #{index}") }
    assert_operator Household.count, :>, PlatformAdmin::HouseholdsController::PAGE_SIZE

    get platform_admin_households_path
    assert_select "a[href^='/platform_admin/households/']", count: PlatformAdmin::HouseholdsController::PAGE_SIZE
  end

  test "operator can suspend and restore a household" do
    post suspend_platform_admin_household_path(@alpha), params: { reason: "Support review" }
    assert_redirected_to platform_admin_household_path(@alpha)
    assert_equal "Support review", @alpha.reload.suspension_reason

    post restore_platform_admin_household_path(@alpha)
    assert_redirected_to platform_admin_household_path(@alpha)
    assert_not @alpha.reload.suspended?
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
