require "test_helper"

class PlatformAdmin::DeletionRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
    @household = Household.create!(name: "Delete Me Kitchen")
    @user = User.create!(email: "delete-me@example.com")
    @household.family_members.create!(name: "Delete Admin", role: "admin", pin: "1234", user: @user)
    @deletion_request = @household.account_deletion_requests.create!(requested_by_user: @user, requested_at: Time.current)
    sign_in_platform_admin(@admin)
  end

  # @card-47.3
  test "permanent deletion requires exact household-name confirmation" do
    create_subscription("sub_wrong_name")

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: "wrong" }

      assert_empty attempted
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert_match "exact household name", flash[:alert]
    assert Household.exists?(@household.id)
    assert @deletion_request.reload.pending?
    assert_not PlatformAuditEvent.where(target_id: @household.id).where("action LIKE ?", "household.%deleti%").exists?
  end

  # @card-47.3
  test "signed-out visitors cannot delete a household" do
    delete platform_admin_session_path
    create_subscription("sub_unauthorized")

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_empty attempted
    end

    assert_redirected_to new_platform_admin_session_path
    assert Household.exists?(@household.id)
    assert @deletion_request.reload.pending?
    assert_not PlatformAuditEvent.exists?(target_id: @household.id, action: "household.permanently_deleted")
    assert_not PlatformAuditEvent.exists?(target_id: @household.id, action: "household.deletion_blocked_by_billing")
  end

  # @card-47.3
  test "permanent deletion cancels every active subscription before removing the household" do
    create_subscription("sub_ok_one")
    create_subscription("sub_ok_two")

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal %w[sub_ok_one sub_ok_two], attempted.sort
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert_not User.exists?(@user.id)
    assert_not AccountDeletionRequest.exists?(@deletion_request.id)
    assert_not Pay::Subscription.exists?(processor_id: %w[sub_ok_one sub_ok_two])
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    assert_not PlatformAuditEvent.exists?(action: "household.deletion_blocked_by_billing", target_id: @household.id)
  end

  # @card-47.3
  test "a partial cancellation failure keeps the household, its billing records and the request" do
    create_subscription("sub_cancels")
    create_subscription("sub_refused")

    stub_stripe_cancellation(failing: { "sub_refused" => Pay::Stripe::Error.new("No such subscription: 'sub_refused'") }) do
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert Household.exists?(@household.id)
    assert User.exists?(@user.id)
    assert @deletion_request.reload.pending?
    assert @household.reload.pay_customers.exists?
    assert_equal "canceled", Pay::Subscription.find_by!(processor_id: "sub_cancels").status
    assert_equal "active", Pay::Subscription.find_by!(processor_id: "sub_refused").status

    assert_match "Household not deleted", flash[:alert]
    assert_match "sub_refused", flash[:alert]
    assert_no_match "sub_cancels", flash[:alert]
    assert_match "confirm the deletion again", flash[:alert]

    assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    audit = PlatformAuditEvent.find_by!(action: "household.deletion_blocked_by_billing", target_id: @household.id)
    assert_equal @admin.id, audit.platform_admin_id
    assert_equal @deletion_request.id, audit.metadata["request_id"]
    assert_equal [ "sub_refused" ], audit.metadata["failed_subscriptions"].map { |f| f["processor_id"] }
    assert_match "No such subscription", audit.metadata["failed_subscriptions"].first["error"]
  end

  # @card-47.3
  test "retrying after a partial failure only cancels what is still active, then deletes" do
    create_subscription("sub_cancels")
    create_subscription("sub_refused")

    stub_stripe_cancellation(failing: { "sub_refused" => Pay::Stripe::Error.new("Stripe is unavailable") }) do
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
    end
    assert Household.exists?(@household.id)

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal [ "sub_refused" ], attempted
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert_not User.exists?(@user.id)
    assert_not AccountDeletionRequest.exists?(@deletion_request.id)
    assert_not Pay::Customer.exists?(owner_type: "Household", owner_id: @household.id)
    assert_not Pay::Subscription.exists?(processor_id: %w[sub_cancels sub_refused])
    assert_equal 1, PlatformAuditEvent.where(action: "household.deletion_blocked_by_billing", target_id: @household.id).count
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  # @card-47.3
  test "a raw Stripe API exception blocks deletion instead of being swallowed" do
    create_subscription("sub_api_down")

    stub_stripe_cancellation(failing: { "sub_api_down" => ::Stripe::APIConnectionError.new("Could not connect to Stripe") }) do
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert Household.exists?(@household.id)
    assert @deletion_request.reload.pending?
    assert_equal "active", Pay::Subscription.find_by!(processor_id: "sub_api_down").status
    assert_match "sub_api_down", flash[:alert]
    audit = PlatformAuditEvent.find_by!(action: "household.deletion_blocked_by_billing", target_id: @household.id)
    assert_match "Stripe::APIConnectionError", audit.metadata["failed_subscriptions"].first["error"]
    assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  # @card-47.3
  test "a past_due subscription Stripe will not cancel blocks deletion and keeps the billing links" do
    create_subscription("sub_past_due", status: "past_due")

    stub_stripe_cancellation(failing: { "sub_past_due" => Pay::Stripe::Error.new("Stripe is unavailable") }) do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal [ "sub_past_due" ], attempted
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert_match "Household not deleted", flash[:alert]
    assert_match "sub_past_due", flash[:alert]
    assert Household.exists?(@household.id)
    assert User.exists?(@user.id)
    assert @deletion_request.reload.pending?
    customer = Pay::Customer.find_by!(owner_type: "Household", owner_id: @household.id)
    subscription = Pay::Subscription.find_by!(processor_id: "sub_past_due")
    assert_equal customer.id, subscription.customer_id
    assert_equal "past_due", subscription.status
    assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    audit = PlatformAuditEvent.find_by!(action: "household.deletion_blocked_by_billing", target_id: @household.id)
    assert_equal [ "sub_past_due" ], audit.metadata["failed_subscriptions"].map { |f| f["processor_id"] }
  end

  # A missed webhook can leave a subscription stored as still billable after
  # Stripe ended it. Cancelling it then fails forever; Stripe's own answer
  # settles it instead of blocking the deletion for good.
  test "a subscription Stripe already ended is brought up to date and does not block deletion" do
    create_subscription("sub_stale", status: "incomplete")
    ended = Pay::Stripe::Error.new("This subscription is already canceled")

    with_stripe_subscription_retrieve("sub_stale" => { status: "incomplete_expired", ended_at: 2.days.ago.to_i }) do
      stub_stripe_cancellation(failing: { "sub_stale" => ended }) do
        delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
      end
    end

    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
  end

  test "a subscription Stripe has no record of does not block deletion" do
    create_subscription("sub_gone", status: "past_due")
    missing = Stripe::InvalidRequestError.new("No such subscription: 'sub_gone'", "id", http_status: 404)

    with_stripe_subscription_retrieve("sub_gone" => missing) do
      stub_stripe_cancellation(failing: { "sub_gone" => Pay::Stripe::Error.new("No such subscription") }) do
        delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
      end
    end

    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
  end

  test "a subscription Stripe is still billing keeps blocking deletion" do
    create_subscription("sub_live", status: "past_due")

    with_stripe_subscription_retrieve("sub_live" => { status: "past_due" }) do
      stub_stripe_cancellation(failing: { "sub_live" => Pay::Stripe::Error.new("Stripe is unavailable") }) do
        delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
      end
    end

    assert_match "Household not deleted", flash[:alert]
    assert Household.exists?(@household.id)
    assert_equal "past_due", Pay::Subscription.find_by!(processor_id: "sub_live").status
  end

  # @card-47.3
  test "permanent deletion cancels every nonterminal subscription and skips terminal ones" do
    nonterminal = %w[active trialing past_due unpaid paused incomplete]
    nonterminal.each { |status| create_subscription("sub_#{status}", status: status) }
    create_subscription("sub_canceled", status: "canceled", ends_at: 1.day.ago)
    create_subscription("sub_incomplete_expired", status: "incomplete_expired")

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal nonterminal.map { |status| "sub_#{status}" }.sort, attempted.sort
    end

    assert_redirected_to platform_admin_deletion_requests_path
    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert_not User.exists?(@user.id)
    assert_not AccountDeletionRequest.exists?(@deletion_request.id)
    assert_not Pay::Customer.exists?(owner_type: "Household", owner_id: @household.id)
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    assert_not PlatformAuditEvent.exists?(action: "household.deletion_blocked_by_billing", target_id: @household.id)
  end

  # @card-47.3
  test "retrying after a partial failure across nonterminal states only reattempts what did not cancel" do
    create_subscription("sub_past_due", status: "past_due")
    create_subscription("sub_paused", status: "paused")
    create_subscription("sub_unpaid", status: "unpaid")

    stub_stripe_cancellation(failing: { "sub_unpaid" => Pay::Stripe::Error.new("Stripe is unavailable") }) do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal %w[sub_past_due sub_paused sub_unpaid].sort, attempted.sort
    end

    assert Household.exists?(@household.id)
    assert @deletion_request.reload.pending?
    assert_equal "canceled", Pay::Subscription.find_by!(processor_id: "sub_past_due").status
    assert_equal "canceled", Pay::Subscription.find_by!(processor_id: "sub_paused").status
    assert_equal "unpaid", Pay::Subscription.find_by!(processor_id: "sub_unpaid").status
    assert_match "sub_unpaid", flash[:alert]
    assert_no_match "sub_past_due", flash[:alert]
    assert_no_match "sub_paused", flash[:alert]

    stub_stripe_cancellation do |attempted|
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

      assert_equal [ "sub_unpaid" ], attempted
    end

    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert_not AccountDeletionRequest.exists?(@deletion_request.id)
    assert_not Pay::Subscription.exists?(processor_id: %w[sub_past_due sub_paused sub_unpaid])
    assert_equal 1, PlatformAuditEvent.where(action: "household.deletion_blocked_by_billing", target_id: @household.id).count
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  test "a failing success audit leaves the household and its pending request" do
    original = PlatformAuditEvent.method(:record!)
    PlatformAuditEvent.define_singleton_method(:record!) do |**kwargs|
      raise "audit store unavailable" if kwargs[:action] == "household.permanently_deleted"

      original.call(**kwargs)
    end

    begin
      delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }
    rescue RuntimeError
      nil
    ensure
      PlatformAuditEvent.define_singleton_method(:record!, original)
    end

    assert Household.exists?(@household.id)
    assert User.exists?(@user.id)
    assert @deletion_request.reload.pending?
    assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  # FP-APPSEC-011
  %w[support billing].each do |role|
    test "#{role} operators cannot permanently delete a household" do
      operator = PlatformAdminAccount.create!(email: "#{role}-op@example.com", password: "correct horse battery staple", role: role)
      delete platform_admin_session_path
      sign_in_platform_admin(operator)
      create_subscription("sub_#{role}_keep")

      stub_stripe_cancellation do |attempted|
        delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

        assert_empty attempted
      end

      assert_redirected_to platform_admin_deletion_requests_path
      assert Household.exists?(@household.id)
      assert @deletion_request.reload.pending?
      assert_equal "active", Pay::Subscription.find_by!(processor_id: "sub_#{role}_keep").status
      assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    end
  end

  test "a privacy operator can permanently delete a household" do
    operator = PlatformAdminAccount.create!(email: "privacy-op@example.com", password: "correct horse battery staple", role: "privacy")
    delete platform_admin_session_path
    sign_in_platform_admin(operator)

    delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  # Owner policy: the minimal Terms, notice and billing evidence is kept
  # indefinitely for now, and nothing purges it; the household's content goes.
  test "deleting a household removes its content and sole member but keeps every piece of evidence" do
    FamilyPlates.config.mode = "hosted"
    recipe = @household.recipes.create!(title: "Gone Soup")
    TermsAssent.accept!(@user, version: Legal::TERMS_VERSION, context: "signup", household: @household)
    notice = TermsNotice.create!(user_id: @user.id, terms_version: "2027-01-01", previous_terms_version: Legal::TERMS_VERSION,
      state: "submitted", submitted_at: Time.current, stated_enforcement_at: 30.days.from_now)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)

    delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

    assert_equal "Household permanently deleted.", flash[:notice]
    assert_not Household.exists?(@household.id)
    assert_not Recipe.exists?(recipe.id)
    assert_not User.exists?(@user.id)
    assert TermsAcceptance.where(user_id: @user.id, household_id: @household.id).exists?
    assert TermsNotice.exists?(notice.id)
    assert BillingConsent.exists?(consent.id)
  ensure
    FamilyPlates.config.reset!
  end

  %w[canceled completed].each do |status|
    test "a #{status} request cannot delete the household" do
      @deletion_request.update_columns(status: status)
      create_subscription("sub_#{status}_keep")

      stub_stripe_cancellation do |attempted|
        delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

        assert_empty attempted
      end

      assert_response :not_found
      assert Household.exists?(@household.id)
      assert_equal "active", Pay::Subscription.find_by!(processor_id: "sub_#{status}_keep").status
      assert_not PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
    end
  end

  private

  def sign_in_platform_admin(admin)
    post platform_admin_session_path, params: {
      email: admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
    }
  end

  def create_subscription(processor_id, status: "active", ends_at: nil)
    @customer ||= @household.set_payment_processor(:stripe, allow_fake: true, processor_id: "cus_del_#{SecureRandom.hex(6)}")
    @customer.subscriptions.create!(name: processor_id, processor_id: processor_id, processor_plan: "monthly", status: status,
                                    ends_at: ends_at, current_period_start: Time.current, current_period_end: 1.month.from_now)
  end

  # Stands in for Stripe's answer about a subscription: its fields, or an
  # error to raise.
  def with_stripe_subscription_retrieve(answers)
    original = Stripe::Subscription.method(:retrieve)
    Stripe::Subscription.define_singleton_method(:retrieve) do |params, *|
      id = params.is_a?(Hash) ? params[:id] : params
      answer = answers.fetch(id)
      raise answer if answer.is_a?(Exception)

      Stripe::Subscription.construct_from({ id: id, object: "subscription" }.merge(answer))
    end
    yield
  ensure
    Stripe::Subscription.define_singleton_method(:retrieve, original)
  end

  # Stands in for Stripe: records each cancellation attempt, raises the error
  # given for a processor id, and otherwise marks the subscription cancelled
  # the way Pay does after Stripe confirms.
  def stub_stripe_cancellation(failing: {})
    attempted = []
    original = Pay::Stripe::Subscription.instance_method(:cancel_now!)
    Pay::Stripe::Subscription.define_method(:cancel_now!) do |**|
      attempted << processor_id
      raise failing[processor_id] if failing.key?(processor_id)

      update!(status: "canceled", ends_at: Time.current)
    end
    yield attempted
  ensure
    Pay::Stripe::Subscription.define_method(:cancel_now!, original)
  end
end
