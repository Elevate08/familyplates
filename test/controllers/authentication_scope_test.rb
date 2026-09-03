require "test_helper"

# current_household answers "whose data may this request see?" and must return
# nil when the answer is nobody's.
#
# It used to fall back to `|| Household.installation`, so an anonymous request
# resolved to a real household and any controller that forgot to check read as
# working code. That is the failure this pins: not a page that breaks today,
# but a scope that goes missing tomorrow and is invisible because the fallback
# quietly supplied a tenant.
class AuthenticationScopeTest < ActiveSupport::TestCase
  setup { Current.reset }
  teardown { Current.reset }

  test "current_household is nil when nobody is signed in" do
    assert_nil controller.send(:current_household),
      "an anonymous request must resolve to no household, not to the installation's"
  end

  test "current_household is the signed-in member's household" do
    Current.family_member = family_members(:one)
    Current.household = family_members(:one).household

    assert_equal households(:one), controller.send(:current_household)
  end

  # The distinction the fallback used to blur: the front door still needs to
  # know which household this box serves, and asks for it by name.
  test "Household.installation answers the front door's question regardless of session" do
    assert_equal households(:one), Household.installation
  end

  test "Household.installation is the oldest household, not the lowest id" do
    assert_operator households(:two).id, :<, households(:one).id,
      "precondition: fixture ids are label hashes, so :two sorts first by id"
    assert_equal households(:one), Household.installation
    assert_not_equal Household.first, Household.installation,
      "if these ever agree, this test has stopped proving anything"
  end

  private

  def controller
    ProfilesController.new
  end
end
