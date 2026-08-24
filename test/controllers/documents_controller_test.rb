require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "index lists user documents" do
    get documents_path
    assert_response :success
  end

  test "show renders document" do
    get document_path(documents(:pending_doc))
    assert_response :success
  end

  test "show explains partial image enrichment separately from processing status" do
    document = documents(:processed_doc)
    document.update_columns(enrichment_status: "partial", enriched_at: Time.current)

    get document_path(document)

    assert_response :success
    assert_select ".badge", text: /Vision: Partial/
    assert_match "Some images could not be described", response.body
  end

  test "index displays skipped image enrichment outcome" do
    document = documents(:processed_doc)
    document.update_columns(enrichment_status: "skipped", enriched_at: Time.current)

    get documents_path

    assert_response :success
    assert_select ".badge", text: /Vision: Skipped/
  end

  test "new renders form" do
    get new_document_path
    assert_response :success
  end

  test "create with valid file saves document and enqueues job" do
    assert_enqueued_with(job: ProcessDocumentJob) do
      post documents_path, params: {
        document: {
          title: "My New Doc",
          file:  fixture_file_upload("sample.txt", "text/plain")
        }
      }
    end
    assert_response :redirect
    doc = @user.documents.order(:created_at).last
    assert_equal "My New Doc", doc.title
    assert doc.file.attached?
    assert_equal "txt", doc.document_type
    follow_redirect!
    assert_match "Processing will begin shortly", response.body
  end

  test "create without file renders unprocessable entity" do
    post documents_path, params: { document: { title: "No File" } }
    assert_response :unprocessable_entity
  end

  test "create without title renders unprocessable entity" do
    post documents_path, params: {
      document: {
        title: "",
        file:  fixture_file_upload("sample.txt", "text/plain")
      }
    }
    assert_response :unprocessable_entity
  end

  test "update changes title" do
    patch document_path(documents(:pending_doc)), params: {
      document: { title: "Updated Title" }
    }
    assert_response :redirect
    assert_equal "Updated Title", documents(:pending_doc).reload.title
  end

  test "update rejects another user's submitted workspace id" do
    document = documents(:pending_doc)
    other_workspace = workspaces(:workspace_two)

    patch document_path(document), params: {
      document: { title: document.title, workspace_ids: [ other_workspace.id ] }
    }

    assert_response :redirect
    assert_empty document.reload.workspaces
    assert_not DocumentWorkspace.exists?(document: document, workspace: other_workspace)
  end

  test "destroy deletes document and redirects" do
    doc = documents(:pending_doc)
    assert_difference -> { @user.documents.count }, -1 do
      delete document_path(doc)
    end
    assert_redirected_to documents_path
  end

  test "cannot access another user's document" do
    other_doc = documents(:failed_doc) # owned by user :two
    get document_path(other_doc)
    assert_response :not_found
  end
end
