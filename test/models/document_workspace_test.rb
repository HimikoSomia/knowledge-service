require "test_helper"

class DocumentWorkspaceTest < ActiveSupport::TestCase
  test "accepts a document and workspace owned by the same user" do
    join = DocumentWorkspace.new(
      document: documents(:pending_doc),
      workspace: workspaces(:workspace_one)
    )

    assert join.valid?
  end

  test "rejects a workspace owned by another user" do
    join = DocumentWorkspace.new(
      document: documents(:pending_doc),
      workspace: workspaces(:workspace_two)
    )

    assert_not join.valid?
    assert_includes join.errors[:workspace], "must belong to the same user as the document"
  end

  test "rejects a document owned by another user" do
    join = DocumentWorkspace.new(
      document: documents(:failed_doc),
      workspace: workspaces(:workspace_one)
    )

    assert_not join.valid?
    assert_includes join.errors[:workspace], "must belong to the same user as the document"
  end

  test "rejects a duplicate document and workspace pair" do
    attributes = {
      document: documents(:pending_doc),
      workspace: workspaces(:workspace_one)
    }
    DocumentWorkspace.create!(attributes)
    duplicate = DocumentWorkspace.new(attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:document_id], "has already been taken"
  end

  test "deleting a document deletes joins but preserves workspaces" do
    workspace = workspaces(:workspace_one)
    document = documents(:pending_doc)
    DocumentWorkspace.create!(workspace: workspace, document: document)

    assert_difference -> { DocumentWorkspace.count }, -1 do
      assert_no_difference -> { Workspace.count } do
        document.destroy!
      end
    end

    assert workspace.reload.persisted?
  end
end
