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

    assert_no_enqueued_jobs do
      assert_nothing_raised { perform_job(service) }
    end

    assert_equal "failed", @document.reload.status
  end

  test "discards invalid input errors without retrying" do
    create_chunks(@document, 1)
    service = embedding_service(error: Embedding::OpenAiEmbeddingService::InvalidInputError.new("blank input"))

    assert_no_enqueued_jobs do
      assert_nothing_raised { perform_job(service) }
    end

    assert_equal "failed", @document.reload.status
  end

  test "marks document failed before retrying a transient service error" do
    create_chunks(@document, 1)
    service = embedding_service(error: Embedding::OpenAiEmbeddingService::ServiceError.new("timeout"))

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      perform_job(service)
    end

    @document.reload
    assert_equal "failed", @document.status
    assert @document.error_message.present?
    assert_not_equal "timeout", @document.error_message
  end

  test "retries service errors for five attempts" do
    create_chunks(@document, 1)

    assert_retry_policy Embedding::OpenAiEmbeddingService::ServiceError, attempts: 5
  end

  test "retries rate limit errors for ten attempts" do
    create_chunks(@document, 1)

    assert_retry_policy Embedding::OpenAiEmbeddingService::RateLimitError, attempts: 10
  end

  test "retries unexpected errors for three attempts" do
    create_chunks(@document, 1)

    assert_retry_policy RuntimeError, attempts: 3, handler_class: StandardError
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
    assert_no_enqueued_jobs do
      assert_nothing_raised { EmbedDocumentJob.perform_now(0) }
    end
  end

  test "is enqueued directly after extraction when enrichment is unnecessary" do
    @document.update_columns(status: "pending", processing_job_execution: 0)

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      ProcessDocumentJob.perform_now(@document.id, @document.processing_generation)
    end
  end

  test "duplicate delivery does not call the embedding provider twice" do
    create_chunks(@document, 1)
    call_count = 0
    service = embedding_service(vectors: fake_vectors(1), counter: -> { call_count += 1 })

    perform_job(service)
    perform_job(service)

    assert_equal 1, call_count
    assert_equal "ready", @document.reload.status
  end

  test "stale provider results cannot overwrite a newer file generation" do
    create_chunks(@document, 1)
    original_generation = @document.processing_generation
    document = @document
    service = embedding_service(vectors: fake_vectors(1), counter: -> {
      document.update_columns(
        processing_generation: original_generation + 1,
        processing_job_id: "replacement-job",
        processing_job_execution: 0,
        status: "pending"
      )
    })

    perform_job(service)

    @document.reload
    assert_equal "pending", @document.status
    assert_nil @document.document_chunks.first.embedding
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
    build_job(service).perform_now
  end

  def build_job(service)
    job = EmbedDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:embedding_service) { service }
    job
  end

  def assert_retry_policy(error_class, attempts:, handler_class: error_class)
    retry_key = [ handler_class ].to_s
    standard_error_key = [ StandardError ].to_s

    before_limit = build_job(embedding_service(error: error_class.new("retryable failure")))
    before_limit.exception_executions[retry_key] = attempts - 2
    before_limit.exception_executions[standard_error_key] = 2 unless retry_key == standard_error_key

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      before_limit.perform_now
    end

    @document.update_columns(status: "embedding", processing_job_id: nil, processing_job_execution: 0)
    at_limit = build_job(embedding_service(error: error_class.new("retryable failure")))
    at_limit.exception_executions[retry_key] = attempts - 1

    assert_no_enqueued_jobs do
      assert_raises(error_class) { at_limit.perform_now }
    end
  end
end
