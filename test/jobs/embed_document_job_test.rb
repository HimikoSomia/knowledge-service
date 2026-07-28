require "test_helper"

class EmbedDocumentJobTest < ActiveJob::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS  # 1536

  setup do
    @user = users(:one)
    @document = @user.documents.new(title: "Embed Test Doc")
    @document.file.attach(
      io:           File.open(file_fixture("sample.txt")),
      filename:     "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    # Set up as fully processed with chunks, ready for embedding
    @document.update_columns(status: "processed", file_checksum: "abc", embedding_status: "pending")
    @original_service_new = Embedding::OpenAiEmbeddingService.method(:new)
    ENV["OPENAI_API_KEY"] = "test-key"
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    if Embedding::OpenAiEmbeddingService.singleton_class.method_defined?(:new, false)
      Embedding::OpenAiEmbeddingService.singleton_class.remove_method(:new)
    end
  end

  test "embeds unprocessed chunks and marks document embedded" do
    create_chunks(@document, 2)
    stub_embedding_service(fake_vectors(2))

    EmbedDocumentJob.perform_now(@document.id)

    @document.reload
    assert_equal "embedded", @document.embedding_status
    assert_not_nil @document.embedded_at
    @document.document_chunks.each do |chunk|
      assert_not_nil chunk.embedding
      assert_equal "text-embedding-3-small", chunk.embedding_model
    end
  end

  test "skips chunks already embedded with the current model" do
    create_chunks(@document, 2)
    vector = Array.new(DB_DIMS, 0.5)
    # Pre-embed one chunk
    @document.document_chunks.order(:chunk_index).first.update_columns(
      embedding: vector, embedding_model: "text-embedding-3-small"
    )

    call_count = 0
    stub_embedding_service_counting([ fake_vectors(1) ]) { |n| call_count = n }

    EmbedDocumentJob.perform_now(@document.id)
    # Only 1 chunk should have been sent to the API
    assert_equal 1, call_count
    assert_equal "embedded", @document.reload.embedding_status
  end

  test "marks not_configured when API key is absent" do
    ENV.delete("OPENAI_API_KEY")
    create_chunks(@document, 1)

    EmbedDocumentJob.perform_now(@document.id)
    assert_equal "not_configured", @document.reload.embedding_status
  end

  test "discards job on ConfigurationError without retrying" do
    create_chunks(@document, 1)
    stub_embedding_service_raising(Embedding::EmbeddingService::ConfigurationError, "bad config")

    # discard_on means the job completes without raising to the test harness
    assert_nothing_raised { EmbedDocumentJob.perform_now(@document.id) }
    assert_equal "failed", @document.reload.embedding_status
  end

  test "marks embedding_failed and sets error_message on ServiceError" do
    create_chunks(@document, 1)
    stub_embedding_service_raising(Embedding::EmbeddingService::ServiceError, "timeout")

    # retry_on catches the error on attempt 1 and re-enqueues — mark_embedding_failed!
    # is still called before the re-raise so the document status reflects the failure.
    EmbedDocumentJob.perform_now(@document.id)
    @document.reload
    assert_equal "failed", @document.embedding_status
    assert_match "timeout", @document.error_message
  end

  test "skips when document is already embedded" do
    @document.update_columns(embedding_status: "embedded")
    # If this ran it would fail because no service is stubbed
    EmbedDocumentJob.perform_now(@document.id)
    assert_equal "embedded", @document.reload.embedding_status
  end

  test "skips when document is not yet processed" do
    @document.update_columns(status: "pending")
    create_chunks(@document, 1)
    EmbedDocumentJob.perform_now(@document.id)
    # Status should remain pending on the document
    assert_equal "pending", @document.reload.status
  end

  test "discards if document does not exist" do
    assert_nothing_raised { EmbedDocumentJob.perform_now(0) }
  end

  test "enqueued by ProcessDocumentJob after successful chunking" do
    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      ProcessDocumentJob.perform_now(@document.id)
    end
  end

  private

  def create_chunks(document, count)
    now = Time.current
    records = Array.new(count) do |i|
      {
        document_id:      document.id,
        chunk_index:       i,
        content:           "Chunk content number #{i + 1}",
        content_checksum:  "checksum#{i}",
        metadata:          {},
        created_at:        now,
        updated_at:        now
      }
    end
    DocumentChunk.insert_all!(records)
    document.update_columns(chunk_count: count)
  end

  def fake_vectors(count)
    Array.new(count) { Array.new(DB_DIMS, 0.1) }
  end

  def stub_embedding_service(vectors)
    stub = @original_service_new.call
    stub.define_singleton_method(:configured?)  { true }
    stub.define_singleton_method(:model)        { "text-embedding-3-small" }
    stub.define_singleton_method(:batch_size)   { 100 }
    stub.define_singleton_method(:embed_texts)  { |_texts| vectors.shift(vectors.size) }
    Embedding::OpenAiEmbeddingService.define_singleton_method(:new) { stub }
  end

  def stub_embedding_service_counting(batched_vectors, &counter)
    call = 0
    stub = @original_service_new.call
    stub.define_singleton_method(:configured?) { true }
    stub.define_singleton_method(:model)       { "text-embedding-3-small" }
    stub.define_singleton_method(:batch_size)  { 100 }
    stub.define_singleton_method(:embed_texts) do |texts|
      call += 1
      counter.call(call)
      batched_vectors[call - 1] || []
    end
    Embedding::OpenAiEmbeddingService.define_singleton_method(:new) { stub }
  end

  def stub_embedding_service_raising(error_class, message)
    stub = @original_service_new.call
    stub.define_singleton_method(:configured?) { true }
    stub.define_singleton_method(:model)       { "text-embedding-3-small" }
    stub.define_singleton_method(:batch_size)  { 100 }
    stub.define_singleton_method(:embed_texts) { |_| raise error_class, message }
    Embedding::OpenAiEmbeddingService.define_singleton_method(:new) { stub }
  end
end
