require "test_helper"

class Retrieval::WorkspaceKnowledgeSearchServiceTest < ActiveSupport::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS

  setup do
    @user = users(:one)
    @workspace = workspaces(:workspace_one)
    @model = "text-embedding-3-small"
  end

  test "embeds the query once and returns document and manual candidates" do
    document = create_ready_document(@user, @workspace)
    create_document_chunk(document, "Document evidence", 1.0)
    source = create_ready_source(@user, @workspace, "Manual evidence")
    create_knowledge_chunk(source, "Manual evidence", 1.0)
    calls = 0

    results = search_service(Array.new(DB_DIMS, 1.0), counter: -> { calls += 1 })
      .search("evidence", workspace_id: @workspace.id, limit: 10)

    assert_equal 1, calls
    assert_equal %w[document note], results.map(&:source_type).sort
  end

  test "excludes sources from other users and workspaces" do
    other_source = create_ready_source(users(:two), workspaces(:workspace_two), "Private")
    create_knowledge_chunk(other_source, "Private evidence", 1.0)
    outside_workspace = @user.workspaces.create!(name: "Outside")
    outside_source = create_ready_source(@user, outside_workspace, "Outside")
    create_knowledge_chunk(outside_source, "Outside evidence", 1.0)
    pending_source = @workspace.knowledge_sources.create!(
      user: @user,
      source_type: "memo",
      title: "Pending",
      content: "Pending evidence",
      status: "pending"
    )
    create_knowledge_chunk(pending_source, "Pending evidence", 1.0)

    results = search_service(Array.new(DB_DIMS, 1.0))
      .search("evidence", workspace_id: @workspace.id, limit: 10)

    assert_empty results
  end

  test "rejects cross-user workspaces before embedding" do
    calls = 0
    service = search_service(Array.new(DB_DIMS, 1.0), counter: -> { calls += 1 })

    assert_raises(ActiveRecord::RecordNotFound) do
      service.search("evidence", workspace_id: workspaces(:workspace_two).id, limit: 10)
    end
    assert_equal 0, calls
  end

  test "raises when embeddings are not configured" do
    service = Retrieval::WorkspaceKnowledgeSearchService.new(
      @user,
      embedding_service: embedding_service(Array.new(DB_DIMS, 1.0), configured: false)
    )

    assert_raises(Retrieval::WorkspaceKnowledgeSearchService::NotConfiguredError) do
      service.search("evidence", workspace_id: @workspace.id, limit: 10)
    end
  end

  private

  def create_ready_document(user, workspace)
    document = user.documents.new(title: "Workspace document")
    document.file.attach(io: StringIO.new("content"), filename: "content.txt", content_type: "text/plain")
    document.save!
    document.update_columns(status: "ready", processed_at: Time.current, embedded_at: Time.current)
    workspace.documents << document
    document
  end

  def create_document_chunk(document, content, vector_seed)
    document.document_chunks.create!(
      chunk_index: 0,
      content: content,
      embedding: Array.new(DB_DIMS, vector_seed),
      embedding_model: @model,
      metadata: {}
    )
  end

  def create_ready_source(user, workspace, content)
    workspace.knowledge_sources.create!(
      user: user,
      source_type: "note",
      title: content,
      content: content,
      status: "ready",
      indexed_at: Time.current
    )
  end

  def create_knowledge_chunk(source, content, vector_seed)
    source.knowledge_chunks.create!(
      chunk_index: 0,
      content: content,
      content_checksum: "checksum-#{source.id}",
      embedding: Array.new(DB_DIMS, vector_seed),
      embedding_model: @model,
      metadata: {}
    )
  end

  def search_service(vector, counter: nil)
    Retrieval::WorkspaceKnowledgeSearchService.new(
      @user,
      embedding_service: embedding_service(vector, counter: counter)
    )
  end

  def embedding_service(vector, configured: true, counter: nil)
    model = @model
    Object.new.tap do |service|
      service.define_singleton_method(:configured?) { configured }
      service.define_singleton_method(:model) { model }
      service.define_singleton_method(:embed_texts) do |_texts|
        counter&.call
        [ vector ]
      end
    end
  end
end
