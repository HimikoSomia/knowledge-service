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
    assert_select "form[action='#{workspace_questions_path(@workspace)}']"
    assert_select "a[href='#{new_workspace_knowledge_source_path(@workspace)}']", text: "Add knowledge"
  end

  test "create derives ownership from the current user" do
    assert_difference -> { @user.workspaces.count }, 1 do
      post workspaces_path, params: { workspace: { name: "Created Workspace", description: "Owned" } }
    end

    workspace = @user.workspaces.order(:created_at).last
    assert_redirected_to workspace_path(workspace)
    assert_equal @user, workspace.user
  end

  test "create renders validation failures as unprocessable entity" do
    assert_no_difference -> { Workspace.count } do
      post workspaces_path, params: { workspace: { name: "", description: "Invalid" } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "update renders validation failures as unprocessable entity" do
    original_name = @workspace.name

    patch workspace_path(@workspace), params: { workspace: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
    assert_equal original_name, @workspace.reload.name
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

  test "search renders indexed manual knowledge" do
    source = knowledge_sources(:note_one)
    source.knowledge_chunks.first.update_columns(
      embedding: Array.new(Embedding::OpenAiEmbeddingService::DB_DIMENSIONS, 1.0),
      embedding_model: "text-embedding-3-small"
    )
    service = Object.new
    service.define_singleton_method(:configured?) { true }
    service.define_singleton_method(:model) { "text-embedding-3-small" }
    service.define_singleton_method(:embed_texts) do |_texts|
      [ Array.new(Embedding::OpenAiEmbeddingService::DB_DIMENSIONS, 1.0) ]
    end
    Embedding::OpenAiEmbeddingService.define_singleton_method(:new) { service }
    get search_workspace_path(@workspace), params: { q: "launch review" }

    assert_response :success
    assert_select "a", text: source.title
    assert_match source.content, response.body
  ensure
    if Embedding::OpenAiEmbeddingService.singleton_class.method_defined?(:new, false)
      Embedding::OpenAiEmbeddingService.singleton_class.remove_method(:new)
    end
  end

  test "cannot access another user's workspace" do
    other_workspace = workspaces(:workspace_two)
    get workspace_path(other_workspace)
    assert_response :not_found
  end

  test "cannot update another user's workspace" do
    other_workspace = workspaces(:workspace_two)

    patch workspace_path(other_workspace), params: { workspace: { name: "Changed" } }

    assert_response :not_found
    assert_equal "Second Workspace", other_workspace.reload.name
  end

  test "cannot delete another user's workspace" do
    other_workspace = workspaces(:workspace_two)

    assert_no_difference -> { Workspace.count } do
      delete workspace_path(other_workspace)
    end

    assert_response :not_found
  end

  test "cannot search another user's workspace" do
    other_workspace = workspaces(:workspace_two)
    get search_workspace_path(other_workspace), params: { q: "test" }
    assert_response :not_found
  end
end
