require "test_helper"

class EmbedDocumentJobTest < ActiveJob::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS

  setup do
    @user = users(:one)
    @document = @user.documents.new(title: "Embed Test Doc")
    @document.file.attach(
      io: File.open(file_fixture("sample.txt")),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    @document.update_columns(status: "embedding", file_checksum: "abc", processed_at: Time.current)
  end

  test "embeds missing chunks and marks document ready" do
    create_chunks(@document, 2)
    perform_job(embedding_service(vectors: fake_vectors(2)))

    @document.reload
    assert_equal "ready", @document.status
    assert_not_nil @document.embedded_at
    @document.document_chunks.each do |chunk|
      assert_not_nil chunk.embedding
      assert_equal "text-embedding-3-small", chunk.embedding_model
    end
  end

  test "embeds only chunks missing the current model" do
    create_chunks(@document, 2)
    vector = Array.new(DB_DIMS, 0.5)
    @document.document_chunks.order(:chunk_index).first.update_columns(
      embedding: vector,
      embedding_model: "text-embedding-3-small"
    )
    call_count = 0
    service = embedding_service(vectors: fake_vectors(1), counter: -> { call_count += 1 })

    perform_job(service)

    assert_equal 1, call_count
    assert_equal "ready", @document.reload.status
  end

  test "marks extracted document processed when API key is absent" do
    create_chunks(@document, 1)
    service = embedding_service(configured: false)

    perform_job(service)

    assert_equal "processed", @document.reload.status
    assert_nil @document.embedded_at
  end

  test "marks document failed on a permanent configuration error" do
    create_chunks(@document, 1)
    service = embedding_service(error: Embedding::OpenAiEmbeddingService::ConfigurationError.new("bad config"))

    assert_nothing_raised { perform_job(service) }

    assert_equal "failed", @document.reload.status
  end

  test "marks document failed before retrying a transient service error" do
    create_chunks(@document, 1)
    service = embedding_service(error: Embedding::OpenAiEmbeddingService::ServiceError.new("timeout"))

    perform_job(service)

    @document.reload
    assert_equal "failed", @document.status
    assert @document.error_message.present?
    assert_not_equal "timeout", @document.error_message
  end

  test "skips a ready document when every chunk uses the current model" do
    create_chunks(@document, 1, embedded: true)
    @document.update_columns(status: "ready")
    service = embedding_service(error: "embedding should not be called")

    perform_job(service)

    assert_equal "ready", @document.reload.status
  end

  test "repairs a ready document that has a newly added unembedded chunk" do
    create_chunks(@document, 1)
    @document.update_columns(status: "ready")

    perform_job(embedding_service(vectors: fake_vectors(1)))

    assert_equal "ready", @document.reload.status
    assert_not_nil @document.document_chunks.first.embedding
  end

  test "skips when extraction has not completed" do
    @document.update_columns(status: "pending", processed_at: nil)
    create_chunks(@document, 1)

    perform_job(embedding_service(vectors: fake_vectors(1)))

    assert_equal "pending", @document.reload.status
  end

  test "discards if document does not exist" do
    assert_nothing_raised { EmbedDocumentJob.perform_now(0) }
  end

  test "is enqueued directly after extraction when enrichment is unnecessary" do
    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      ProcessDocumentJob.perform_now(@document.id)
    end
  end

  private

  def create_chunks(document, count, embedded: false)
    now = Time.current
    records = Array.new(count) do |index|
      {
        document_id: document.id,
        chunk_index: index,
        content: "Chunk content number #{index + 1}",
        content_checksum: "checksum#{index}",
        embedding: embedded ? Array.new(DB_DIMS, 0.5) : nil,
        embedding_model: embedded ? "text-embedding-3-small" : nil,
        metadata: {},
        created_at: now,
        updated_at: now
      }
    end
    DocumentChunk.insert_all!(records)
    document.update_columns(chunk_count: count)
  end

  def fake_vectors(count)
    Array.new(count) { Array.new(DB_DIMS, 0.1) }
  end

  def embedding_service(vectors: [], configured: true, error: nil, counter: nil)
    Object.new.tap do |service|
      service.define_singleton_method(:configured?) { configured }
      service.define_singleton_method(:model) { "text-embedding-3-small" }
      service.define_singleton_method(:batch_size) { 100 }
      service.define_singleton_method(:embed_texts) do |_texts|
        counter&.call
        raise error if error

        vectors
      end
    end
  end

  def perform_job(service)
    job = EmbedDocumentJob.new(@document.id)
    job.define_singleton_method(:embedding_service) { service }
    job.perform_now
  end
end
