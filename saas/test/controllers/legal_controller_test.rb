require "test_helper"

class LegalControllerTest < ActionDispatch::IntegrationTest
  setup { FamilyPlates.config.mode = "hosted" }
  teardown { FamilyPlates.config.reset! }

  test "terms and privacy are public" do
    get terms_path
    assert_response :success
    assert_select "h1", text: "Terms of Service"

    get privacy_path
    assert_response :success
    assert_select "h1", text: "Privacy Policy"
  end

  test "the terms restrict the service to the United States" do
    get terms_path

    assert_includes response.body, "offered only to residents of the United States"
  end

  test "hosted pages link the terms and privacy policy in the footer" do
    get new_session_path

    assert_select "body > footer a[href=?]", terms_path
    assert_select "body > footer a[href=?]", privacy_path
  end

  test "a suspended household can still read the terms" do
    household = households(:one)
    user = User.create!(email: "suspended@example.com")
    member = household.family_members.create!(name: "Suspended Admin", role: "admin", pin: "1234", user: user)
    household.update!(suspended_at: Time.current, suspension_reason: "Payment review")
    sign_in_user(user)
    sign_in_as(member)

    get terms_path

    assert_response :success
  end

  test "appliance mode has no legal footer" do
    FamilyPlates.config.mode = "appliance"
    get new_session_path

    assert_select "a[href=?]", terms_path, false
  end

  DRAFT_NOTICE = "Draft. Not in effect. Stasis State LLC is a proposed name and has not been formed. " \
    "This page is not a contract with that company. Do not pay, and do not treat signup as acceptance " \
    "of a contract with that company, until this draft notice is removed and the operator is named " \
    "without this notice."
  DRAFT_OPERATOR = "[DRAFT TARGET, NOT FORMED: Stasis State LLC]"

  test "each legal draft opens with the full not-in-effect notice" do
    [ terms_path, privacy_path ].each do |path|
      get path

      assert_select "main > article > div > p:first-child", count: 1 do |notice|
        assert_equal DRAFT_NOTICE, notice.text.squish, path
      end
    end
  end

  test "each legal draft names the operator only as a marked, unformed target" do
    [ terms_path, privacy_path ].each do |path|
      get path

      assert_select "main > article > div > p:nth-of-type(2)", count: 1 do |identity|
        assert_includes identity.text.squish, %(operated by #{DRAFT_OPERATOR} ("we", "us")), path
      end
      assert_not_includes document_text, "operated by Stasis State LLC", path
      # Outside the draft notice, every mention of the company carries the marker.
      assert_equal document_text.scan(DRAFT_OPERATOR).size + 1, document_text.scan("Stasis State LLC").size, path
    end
  end

  test "the privacy contact names the marked target with an unresolved address and email" do
    get privacy_path

    assert_select "main > article > div > h2:last-of-type", text: "Contact"
    assert_select "main > article > div > h2:last-of-type + p", count: 1 do |contact|
      assert_includes contact.text.squish, DRAFT_OPERATOR
      assert_includes contact.text.squish, "[MAILING ADDRESS]"
      assert_includes contact.text.squish, "[CONTACT EMAIL]"
    end
  end

  test "the drafts keep their unresolved placeholders" do
    get terms_path
    [ "[CONTACT EMAIL]", "[REFUND POLICY:", "[STATE]" ].each do |placeholder|
      assert_includes document_text, placeholder
    end

    get privacy_path
    [ "[CONTACT EMAIL]", "[MAILING ADDRESS]", "[EMAIL PROVIDER]", "[HOSTING PROVIDER]", "[BACKUP RETENTION PERIOD]" ].each do |placeholder|
      assert_includes document_text, placeholder
    end
  end

  test "legal pages keep FamilyPlates branding and a footer that names no company" do
    { terms_path => "Terms of Service", privacy_path => "Privacy Policy" }.each do |path, title|
      get path

      assert_select "title", text: "#{title} | FamilyPlates"
      assert_select "main > article > header > p:first-child", text: "FamilyPlates"
      assert_select "main > article > header > h1", text: title
      assert_select "main > article > footer", count: 1 do |footer|
        assert_not_includes footer.text, "Stasis State LLC", path
        assert_select "a[href=?]", terms_path
        assert_select "a[href=?]", privacy_path
      end
      assert_select "body > footer", count: 1 do |footer|
        assert_not_includes footer.text, "Stasis State LLC", path
      end
    end
  end

  private
    # The rendered legal document body, whitespace-normalized.
    def document_text
      css_select("main > article > div").text.squish
    end
end
