require "test_helper"

# The Google service account JSON is a private key. It was stored in clear text
# and rendered back into the settings page on every visit, so it reached the DOM,
# the browser cache, and any screenshot of that screen.
class Admin::CalendarCredentialTest < ActionDispatch::IntegrationTest
  CREDENTIAL = {
    "type" => "service_account",
    "project_id" => "familyplates-test",
    "private_key_id" => "abc123",
    "private_key" => "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\n-----END PRIVATE KEY-----\n",
    "client_email" => "familyplates@familyplates-test.iam.gserviceaccount.com"
  }.to_json.freeze

  setup do
    @household = households(:one)
    @household.update!(google_service_account_json: CREDENTIAL)
    sign_in_as(family_members(:one))
  end

  test "the stored credential is not readable in the database" do
    stored = Household.connection.select_value(
      "SELECT google_service_account_json FROM households WHERE id = #{@household.id}"
    )

    assert_not_nil stored
    assert_not_includes stored, "BEGIN PRIVATE KEY", "the key must not sit in the column in clear text"
    assert_not_includes stored, "familyplates@familyplates-test.iam.gserviceaccount.com"
    assert_equal CREDENTIAL, @household.reload.google_service_account_json,
      "but the application must still read it back"
  end

  test "the settings page never renders the stored credential" do
    get edit_admin_calendar_path

    assert_response :success
    assert_not_includes response.body, "BEGIN PRIVATE KEY"
    assert_not_includes response.body, "abc123"
    assert_not_includes response.body, "private_key"
    assert_includes response.body, "Key Configured", "it should still say a key is present"
  end

  test "saving with a blank credential field leaves the stored key alone" do
    patch admin_calendar_path, params: {
      household: { google_calendar_id: "family@group.calendar.google.com", google_service_account_json: "" }
    }

    assert_equal CREDENTIAL, @household.reload.google_service_account_json,
      "a blank field means unchanged, not cleared"
    assert_equal "family@group.calendar.google.com", @household.google_calendar_id
  end

  test "a new credential replaces the old one" do
    replacement = CREDENTIAL.sub("abc123", "def456")

    patch admin_calendar_path, params: { household: { google_service_account_json: replacement } }

    assert_equal replacement, @household.reload.google_service_account_json
  end

  test "removing the credential requires an explicit choice" do
    patch admin_calendar_path, params: {
      household: { google_service_account_json: "", remove_google_service_account_json: "1" }
    }

    assert_nil @household.reload.google_service_account_json
  end

  test "the field shows a Configured badge when a key is stored, and not otherwise" do
    get edit_admin_calendar_path
    assert_select "[data-configured-field-target=indicator]", 1
    assert_select "[data-controller=configured-field]", 1

    @household.update!(google_service_account_json: nil)
    get edit_admin_calendar_path
    assert_select "[data-configured-field-target=indicator]", 0,
      "nothing is stored, so nothing should claim to be configured"
  end
end
