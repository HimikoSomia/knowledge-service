require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  test "requires a name" do
    workspace = users(:one).workspaces.new(name: "   ")

    assert_not workspace.valid?
    assert_includes workspace.errors[:name], "can't be blank"
  end

  test "deleting a workspace deletes joins but preserves documents" do
    workspace = workspaces(:workspace_one)
    document = documents(:pending_doc)
    DocumentWorkspace.create!(workspace: workspace, document: document)

    assert_difference -> { DocumentWorkspace.count }, -1 do
      assert_no_difference -> { Document.count } do
        workspace.destroy!
      end
    end

    assert document.reload.persisted?
  end
end
