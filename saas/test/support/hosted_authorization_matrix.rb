# The hosted edition's rows for AuthorizationMatrixTest: its routes, the
# records they take, and the operator - a platform admin, the one kind of
# visitor an appliance does not have. test_helper.rb loads this on the hosted
# bundle only; on an appliance the matrix runs without it, and its "every
# route has a row" check then proves none of these routes exist there.
module HostedAuthorizationMatrix
  ROWS = {
      # Sign-up. Open by design: it is how a new household gets in.
      "GET /signup" => [ :open ],
      "GET /signup/new" => [ :open ],
      "POST /signup" => [ :open ],
      "GET /signup/verify" => [ :open ],
      "POST /signup/verify" => [ :open ],
      # Billing. Viewing is for the household; changing it is for the organizer.
      "GET /subscription" => [ :household ],
      "POST /subscription" => [ :organizer ],
      "DELETE /subscription" => [ :organizer ],
      "GET /subscription/portal" => [ :organizer ],
      # Where a suspended household is sent.
      "GET /suspended" => [ :household ],
      # Asking the operator to delete the household: organizer only.
      "POST /account_data/request_deletion" => [ :organizer ],
      # Support threads belong to the household.
      "GET /support_threads" => [ :household ],
      "POST /support_threads" => [ :household ],
      "GET /support_threads/:id" => [ :household, {}, :not_found ],
      "PATCH /support_threads/:id/resolve" => [ :household, {}, :not_found ],
      "POST /support_threads/:support_thread_id/messages" => [ :household, {}, :not_found ],
      # Platform console. Its sign-in pages are open.
      "GET /platform_admin/session/new" => [ :open ],
      "POST /platform_admin/session" => [ :open ],
      # Signing out, or never signed in: either way the visitor lands on sign-in.
      "DELETE /platform_admin/session" => [ :operator, { operator: :operator_sign_in } ],
      "GET /platform_admin" => [ :operator ],
      "GET /platform_admin/audit_events" => [ :operator ],
      "GET /platform_admin/deletion_requests" => [ :operator ],
      "DELETE /platform_admin/deletion_requests/:id" => [ :operator ],
      "GET /platform_admin/promotion_programs" => [ :operator ],
      "POST /platform_admin/promotion_programs" => [ :operator ],
      "PATCH /platform_admin/promotion_programs/:id" => [ :operator ],
      "PUT /platform_admin/promotion_programs/:id" => [ :operator ],
      "GET /platform_admin/bulk_operations" => [ :operator ],
      "GET /platform_admin/bulk_operations/new" => [ :operator ],
      "POST /platform_admin/bulk_operations" => [ :operator ],
      "POST /platform_admin/bulk_operations/preview" => [ :operator ],
      "GET /platform_admin/households" => [ :operator ],
      "GET /platform_admin/households/:id" => [ :operator ],
      "POST /platform_admin/households/:id/suspend" => [ :operator ],
      "POST /platform_admin/households/:id/restore" => [ :operator ],
      "POST /platform_admin/households/:id/cancel_subscription" => [ :operator ],
      "POST /platform_admin/households/:id/comp" => [ :operator ],
      "POST /platform_admin/households/:id/charges/:charge_id/refund" => [ :operator ],
      "GET /platform_admin/support_threads" => [ :operator ],
      "GET /platform_admin/support_threads/:id" => [ :operator ],
      "POST /platform_admin/support_threads/:id/reply" => [ :operator ],
      "PATCH /platform_admin/support_threads/:id/resolve" => [ :operator ],
      "PATCH /platform_admin/support_threads/:id/reopen" => [ :operator ],
      "PATCH /platform_admin/support_threads/:id/change_status" => [ :operator ]
  }.freeze

  EXEMPT = {
    "GET /pay/payments/:id" => "Pay engine page, keyed by a Stripe PaymentIntent id.",
    "POST /pay/webhooks/stripe" => "Authenticated by Stripe's signature (stripe_webhook_states_test)."
  }.freeze

  PARAMS = {
    [ "support_threads", "id" ] => :support_thread,
    [ "support_messages", "support_thread_id" ] => :support_thread,
    [ "platform_admin/deletion_requests", "id" ] => :deletion_request,
    [ "platform_admin/promotion_programs", "id" ] => :promotion_program,
    [ "platform_admin/households", "id" ] => :household,
    [ "platform_admin/households", "charge_id" ] => :charge,
    [ "platform_admin/support_threads", "id" ] => :support_thread
  }.freeze

  # Mixed into AuthorizationMatrixTest.
  module TestHelpers
    private

    def sign_in_operator
      admin = PlatformAdminAccount.create!(email: "matrix-operator@example.com", password: "correct horse battery staple")
      post platform_admin_session_path, params: {
        email: admin.email, password: "correct horse battery staple",
        otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
      }
      assert_redirected_to platform_admin_root_path, "precondition: the operator signed in"
    end

    def operator_sign_in_redirect?(location)
      response.redirect? && location == new_platform_admin_session_path
    end

    def hosted_records(household)
      {
        support_thread: household.support_threads.create!(subject: "Matrix thread").id,
        deletion_request: household.account_deletion_requests.create!(requested_at: Time.current).id,
        promotion_program: PromotionProgram.create!(name: "Matrix", code: "MATRIX", discount_percent: 10).id,
        charge: matrix_charge(household).id
      }
    end

    def hosted_foreign_records(other)
      { support_thread: other.support_threads.create!(subject: "Miller thread").id }
    end

    def matrix_charge(household)
      household.set_payment_processor :fake_processor, allow_fake: true
      household.payment_processor.charges.create!(processor_id: "ch_matrix", amount: 400)
    end
  end
end
