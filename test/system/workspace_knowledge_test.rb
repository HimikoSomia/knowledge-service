require "application_system_test_case"

class WorkspaceKnowledgeTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    sign_in_through_browser_as(@user)
  end

  test "creates an owned note through the workspace UI" do
    visit workspace_path(@workspace)
    click_link "Add knowledge"

    select "Note", from: "Type"
    fill_in "Title", with: "Browser acceptance note"
    fill_in "Content", with: "The browser flow stores this workspace fact."

    assert_difference -> { @workspace.knowledge_sources.count }, 1 do
      click_button "Create Knowledge source"
      assert_current_path workspace_path(@workspace)
    end

    assert_text "Browser acceptance note"
    assert_text "Pending"

    source = @workspace.knowledge_sources.find_by!(title: "Browser acceptance note")
    assert_equal @user, source.user
    assert_equal "The browser flow stores this workspace fact.", source.content
  end
end
