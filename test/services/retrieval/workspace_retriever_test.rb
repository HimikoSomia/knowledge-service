require "test_helper"

class Retrieval::WorkspaceRetrieverTest < ActiveSupport::TestCase
  FakeChunk = Retrieval::WorkspaceKnowledgeSearchService::Candidate

  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
  end

  teardown do
    ENV.delete("WORKSPACE_QA_MAX_DISTANCE")
    ENV.delete("WORKSPACE_QA_MAX_RESULTS_PER_SOURCE")
    ENV.delete("WORKSPACE_QA_MAX_CONTEXT_CHARS")
  end

  test "returns source-neutral results scoped to the workspace" do
    search = fake_search([ fake_chunk(id: 7, distance: 0.2, page_number: 4) ])
    result = Retrieval::WorkspaceRetriever.new(@user, @workspace, search_service: search)
      .retrieve("What happened?").first

    assert_equal @workspace.id, search.workspace_id
    assert_equal "document", result.source_type
    assert_equal 7, result.chunk_id
    assert_equal "Source document", result.source_title
    assert_equal "Page 4", result.source_locator
  end

  test "preserves note source identity in neutral results" do
    search = fake_search([
      fake_chunk(id: 8, source_type: "note", source_id: 22, source_title: "Launch note")
    ])

    result = Retrieval::WorkspaceRetriever.new(@user, @workspace, search_service: search)
      .retrieve("What happened?").first

    assert_equal "note", result.source_type
    assert_equal 22, result.source_id
    assert_equal "Launch note", result.source_title
  end

  test "filters weak matches and limits repeated chunks from one source" do
    ENV["WORKSPACE_QA_MAX_DISTANCE"] = "0.4"
    ENV["WORKSPACE_QA_MAX_RESULTS_PER_SOURCE"] = "1"
    chunks = [
      fake_chunk(id: 1, source_id: 10, distance: 0.1),
      fake_chunk(id: 2, source_id: 10, distance: 0.2),
      fake_chunk(id: 3, source_id: 11, distance: 0.8)
    ]

    results = Retrieval::WorkspaceRetriever.new(@user, @workspace, search_service: fake_search(chunks))
      .retrieve("question")

    assert_equal [ 1 ], results.map(&:chunk_id)
  end

  test "rejects a workspace not owned by the user before searching" do
    search = fake_search([])
    retriever = Retrieval::WorkspaceRetriever.new(@user, workspaces(:workspace_two), search_service: search)

    assert_raises(ActiveRecord::RecordNotFound) { retriever.retrieve("question") }
    assert_nil search.workspace_id
  end

  test "does not exceed the configured context budget" do
    ENV["WORKSPACE_QA_MAX_CONTEXT_CHARS"] = "35"
    chunks = [
      fake_chunk(id: 1, distance: 0.1, content: "a" * 25),
      fake_chunk(id: 2, source_id: 11, distance: 0.2, content: "b" * 20)
    ]

    results = Retrieval::WorkspaceRetriever.new(@user, @workspace, search_service: fake_search(chunks))
      .retrieve("question")

    assert_equal [ 1 ], results.map(&:chunk_id)
    assert_operator results.sum { |result| result.content.length }, :<=, 35
  end

  private

  def fake_chunk(id:, source_type: "document", source_id: 10, source_title: "Source document",
                 distance: 0.2, page_number: nil, content: nil)
    FakeChunk.new(
      chunk_id: id,
      content: content || "Relevant workspace content #{id}",
      source_type: source_type,
      source_id: source_id,
      source_title: source_title,
      source_locator: page_number ? "Page #{page_number}" : "Chunk #{id + 1}",
      metadata: {},
      neighbor_distance: distance
    )
  end

  def fake_search(chunks)
    Object.new.tap do |service|
      service.define_singleton_method(:search) do |_, workspace_id:, limit:|
        @workspace_id = workspace_id
        @limit = limit
        chunks
      end
      service.define_singleton_method(:workspace_id) { @workspace_id }
    end
  end
end
