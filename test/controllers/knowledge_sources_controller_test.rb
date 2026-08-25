require "test_helper"

class KnowledgeSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    sign_in_as(@user)
  end

  test "new renders the source form" do
    get new_workspace_knowledge_source_path(@workspace, source_type: "memo")

    assert_response :success
    assert_select "form[action='#{workspace_knowledge_sources_path(@workspace)}']"
    assert_select "select[name='knowledge_source[source_type]'] option[selected]", text: "Memo"
  end

  test "create derives ownership and queues indexing" do
    assert_difference -> { @workspace.knowledge_sources.count }, 1 do
      assert_enqueued_jobs 1, only: IndexKnowledgeSourceJob do
        post workspace_knowledge_sources_path(@workspace), params: {
          knowledge_source: {
            source_type: "note",
            title: "Release plan",
            content: "Ship after the final review.",
            user_id: users(:two).id
          }
        }
      end
    end

    source = @workspace.knowledge_sources.recent_first.first
    assert_redirected_to workspace_path(@workspace)
    assert_equal @user, source.user
    assert source.pending?
  end

  test "create renders validation errors" do
    assert_no_difference -> { KnowledgeSource.count } do
      post workspace_knowledge_sources_path(@workspace), params: {
        knowledge_source: { source_type: "note", title: "", content: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "update requeues the source with a new generation" do
    source = knowledge_sources(:note_one)
    previous_generation = source.indexing_generation

    assert_enqueued_jobs 1, only: IndexKnowledgeSourceJob do
      patch workspace_knowledge_source_path(@workspace, source), params: {
        knowledge_source: { source_type: "memo", title: "Updated", content: "Updated facts" }
      }
    end

    source.reload
    assert_redirected_to workspace_path(@workspace)
    assert_equal "Updated", source.title
    assert source.memo?
    assert_equal previous_generation + 1, source.indexing_generation
  end

  test "destroy removes an owned source and its chunks" do
    source = knowledge_sources(:note_one)

    assert_difference -> { KnowledgeSource.count }, -1 do
      assert_difference -> { KnowledgeChunk.count }, -1 do
        delete workspace_knowledge_source_path(@workspace, source)
      end
    end

    assert_redirected_to workspace_path(@workspace)
  end

  test "cannot access or mutate another user's source" do
    other_workspace = workspaces(:workspace_two)
    other_source = knowledge_sources(:memo_two)

    get edit_workspace_knowledge_source_path(other_workspace, other_source)
    assert_response :not_found

    patch workspace_knowledge_source_path(other_workspace, other_source), params: {
      knowledge_source: { title: "Changed", content: "Changed", source_type: "memo" }
    }
    assert_response :not_found

    assert_no_difference -> { KnowledgeSource.count } do
      delete workspace_knowledge_source_path(other_workspace, other_source)
    end
    assert_response :not_found
    assert_equal "Private memo", other_source.reload.title
  end
end
