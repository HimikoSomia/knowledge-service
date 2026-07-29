require "test_helper"

class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @workspace = workspaces(:workspace_one)
  end

  test "show renders workspace page" do
    get workspace_path(@workspace)
    assert_response :success
    assert_select "h1", @workspace.name
  end

  test "search renders workspace show page with query" do
    get search_workspace_path(@workspace), params: { q: "test query" }
    assert_response :success
    assert_select "input[name='q'][value='test query']"
  end

  test "search without query renders show page without results" do
    get search_workspace_path(@workspace)
    assert_response :success
  end

  test "search shows not-configured message when embedding service unavailable" do
    ENV.delete("OPENAI_API_KEY")
    get search_workspace_path(@workspace), params: { q: "test" }
    assert_response :success
    assert_match "Search is not available", response.body
  ensure
    ENV["OPENAI_API_KEY"] = "test-key"
  end

  test "cannot access another user's workspace" do
    other_workspace = workspaces(:workspace_two)
    get workspace_path(other_workspace)
    assert_response :not_found
  end

  test "cannot search another user's workspace" do
    other_workspace = workspaces(:workspace_two)
    get search_workspace_path(other_workspace), params: { q: "test" }
    assert_response :not_found
  end
end

