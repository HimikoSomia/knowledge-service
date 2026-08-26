require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  test "signs in and opens an owned workspace" do
    workspace = workspaces(:workspace_one)

    visit workspace_path(workspace)

    assert_current_path new_session_path
    sign_in_through_browser_as(users(:one))

    assert_current_path workspace_path(workspace)
    assert_selector "h1", text: workspace.name
    assert_no_text workspaces(:workspace_two).name
  end
end
