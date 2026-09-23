require "test_helper"

# The centered shell used to be copied into every auth and profile page. One
# template owns it now, and profile select keeps the tighter padding it had.
class CenteredPageShellTest < ActionDispatch::IntegrationTest
  SHELL = "min-h-[75vh] flex flex-col items-center justify-center"

  test "the centered page shell is defined in one template" do
    hits = Dir[Rails.root.join("app/views/**/*.erb")].select { |path| File.read(path).include?(SHELL) }

    assert_equal [ "app/views/shared/_centered_page.html.erb" ],
      hits.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  test "sign-in renders the shared shell with the standard padding" do
    get new_session_path

    assert_response :success
    assert_match(/class="min-h-\[75vh\] flex flex-col items-center justify-center py-6 sm:py-12 px-4"/, response.body)
    assert_no_match(/min-h-\[75vh\][^"]*px-2/, response.body)
  end

  test "profile select renders the shared shell with its own padding" do
    get select_profile_path

    assert_response :success
    assert_match(/class="min-h-\[75vh\] flex flex-col items-center justify-center py-6 sm:py-12 px-2 sm:px-4"/, response.body)
    assert_match(/data-controller="dropdown"/, response.body)
  end
end
