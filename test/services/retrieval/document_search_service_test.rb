require "test_helper"

class Retrieval::DocumentSearchServiceTest < ActiveSupport::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS  # 1536

  setup do
    @user_one = users(:one)
    @user_two = users(:two)
    ENV["OPENAI_API_KEY"] = "test-key"
    @original_service_new = Embedding::OpenAiEmbeddingService.method(:new)
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    if Embedding::OpenAiEmbeddingService.singleton_class.method_defined?(:new, false)
      Embedding::OpenAiEmbeddingService.singleton_class.remove_method(:new)
    end
  end

  test "returns chunks closest to the query vector" do
    doc = create_processed_document(@user_one, "Tech Guide")
    near_chunk   = create_embedded_chunk(doc, 0, content: "Python is a programming language", vector_seed: 1.0)
    far_chunk    = create_embedded_chunk(doc, 1, content: "Cheese is made from milk",        vector_seed: 0.0)

    # Query vector identical to near_chunk → cosine distance 0
    stub_embedding_service(Array.new(DB_DIMS, 1.0))

    service = Retrieval::DocumentSearchService.new(@user_one)
    results = service.search("Python programming")

    assert results.any?, "Expected at least one result"
    assert_equal near_chunk.id, results.first.id
  end

  test "excludes chunks from other users' documents" do
    other_doc  = create_processed_document(@user_two, "Private Doc")
    create_embedded_chunk(other_doc, 0, content: "Secret content", vector_seed: 1.0)

    stub_embedding_service(Array.new(DB_DIMS, 1.0))

    results = Retrieval::DocumentSearchService.new(@user_one).search("anything")
    ids = results.map(&:id)
    assert_empty(ids.select { |id| DocumentChunk.find(id).document.user_id == @user_two.id })
  end

  test "excludes chunks from documents that are not in processed status" do
    doc = create_processed_document(@user_one, "Draft")
    doc.update_columns(status: "pending")
    create_embedded_chunk(doc, 0, content: "Draft content", vector_seed: 1.0)

    stub_embedding_service(Array.new(DB_DIMS, 1.0))
    results = Retrieval::DocumentSearchService.new(@user_one).search("draft")
    assert_empty results.to_a
  end

  test "excludes chunks without embeddings" do
    doc = create_processed_document(@user_one, "Partial")
    DocumentChunk.create!(
      document:    doc,
      chunk_index: 0,
      content:     "No embedding yet",
      metadata:    {}
    )

    stub_embedding_service(Array.new(DB_DIMS, 1.0))
    results = Retrieval::DocumentSearchService.new(@user_one).search("anything")
    assert_empty results.to_a
  end

  test "excludes chunks embedded with a different model" do
    doc = create_processed_document(@user_one, "Old embeddings")
    chunk = create_embedded_chunk(doc, 0, content: "Old model content", vector_seed: 1.0)
    chunk.update_columns(embedding_model: "text-embedding-ada-002")

    ENV["OPENAI_EMBEDDING_MODEL"] = "text-embedding-3-small"
    stub_embedding_service(Array.new(DB_DIMS, 1.0))

    results = Retrieval::DocumentSearchService.new(@user_one).search("old")
    assert_empty results.to_a
  end

  test "restricts results to specified workspace" do
    doc_in     = create_processed_document(@user_one, "In workspace")
    doc_out    = create_processed_document(@user_one, "Out of workspace")
    workspace  = @user_one.workspaces.create!(name: "My Workspace")
    workspace.documents << doc_in

    create_embedded_chunk(doc_in,  0, content: "Inside",  vector_seed: 1.0)
    create_embedded_chunk(doc_out, 0, content: "Outside", vector_seed: 1.0)

    stub_embedding_service(Array.new(DB_DIMS, 1.0))
    results = Retrieval::DocumentSearchService.new(@user_one)
                                              .search("topic", workspace_id: workspace.id)
    document_ids = results.map { |c| c.document_id }.uniq
    assert_includes document_ids, doc_in.id
    assert_not_includes document_ids, doc_out.id
  end

  test "raises EmptyQueryError for blank query" do
    assert_raises(Retrieval::DocumentSearchService::EmptyQueryError) do
      Retrieval::DocumentSearchService.new(@user_one).search("   ")
    end
  end

  test "raises NotConfiguredError when API key is absent" do
    ENV.delete("OPENAI_API_KEY")
    assert_raises(Retrieval::DocumentSearchService::NotConfiguredError) do
      Retrieval::DocumentSearchService.new(@user_one).search("test")
    end
  end

  private

  def create_processed_document(user, title)
    doc = user.documents.new(title: title)
    doc.file.attach(io: StringIO.new("test"), filename: "test.txt", content_type: "text/plain")
    doc.save!
    doc.update_columns(status: "processed", embedding_status: "embedded")
    doc
  end

  def create_embedded_chunk(doc, index, content:, vector_seed: 0.5)
    chunk = doc.document_chunks.create!(
      chunk_index:     index,
      content:         content,
      embedding:       Array.new(DB_DIMS, vector_seed),
      embedding_model: ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
      metadata:        {}
    )
    chunk
  end

  def stub_embedding_service(query_vector)
    stub = @original_service_new.call
    stub.define_singleton_method(:configured?) { true }
    stub.define_singleton_method(:embed_texts) { |_| [ query_vector ] }
    Embedding::OpenAiEmbeddingService.define_singleton_method(:new) { stub }
  end
end
