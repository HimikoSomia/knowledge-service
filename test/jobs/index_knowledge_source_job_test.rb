require "test_helper"

class IndexKnowledgeSourceJobTest < ActiveJob::TestCase
  DB_DIMS = Embedding::OpenAiEmbeddingService::DB_DIMENSIONS

  setup do
    @source = workspaces(:workspace_one).knowledge_sources.create!(
      user: users(:one),
      source_type: "note",
      title: "Indexing test",
      content: "A grounded fact for this workspace."
    )
  end

  test "chunks and embeds a source before marking it ready" do
    perform_job(embedding_service(vectors: fake_vectors(1)))

    @source.reload
    assert @source.ready?
    assert_not_nil @source.indexed_at
    assert_equal 1, @source.knowledge_chunks.count
    assert_equal "text-embedding-3-small", @source.knowledge_chunks.first.embedding_model
    assert_not_nil @source.knowledge_chunks.first.embedding
  end

  test "marks a source unindexed when embedding is not configured" do
    perform_job(embedding_service(configured: false))

    assert @source.reload.unindexed?
    assert_equal "not_configured", @source.error_code
    assert_empty @source.knowledge_chunks
  end

  test "duplicate delivery does not call the provider twice" do
    calls = 0
    job = build_job(embedding_service(vectors: fake_vectors(1), counter: -> { calls += 1 }))

    job.perform_now
    job.perform_now

    assert_equal 1, calls
    assert @source.reload.ready?
  end

  test "stale provider results cannot replace a newer generation" do
    source = @source
    job = build_job(embedding_service(vectors: fake_vectors(1), counter: -> {
      source.update_columns(
        status: "pending",
        indexing_generation: source.indexing_generation + 1,
        indexing_job_id: "replacement-job",
        indexing_job_execution: 0
      )
    }))

    job.perform_now

    assert @source.reload.pending?
    assert_equal "replacement-job", @source.indexing_job_id
    assert_empty @source.knowledge_chunks
  end

  test "transient provider errors preserve the claim and enqueue a retry" do
    job = build_job(embedding_service(error: Embedding::OpenAiEmbeddingService::ServiceError.new("timeout")))

    assert_enqueued_jobs 1, only: IndexKnowledgeSourceJob do
      job.perform_now
    end

    assert @source.reload.indexing?
    assert_equal job.job_id, @source.indexing_job_id
  end

  test "exhausted transient retries record a safe error" do
    job = build_job(embedding_service(error: Embedding::OpenAiEmbeddingService::ServiceError.new("timeout")))
    retry_key = [ Embedding::OpenAiEmbeddingService::ServiceError ].to_s
    job.exception_executions[retry_key] = 4

    assert_no_enqueued_jobs { assert_nothing_raised { job.perform_now } }

    assert @source.reload.failed?
    assert_equal "provider_unavailable", @source.error_code
    assert_nil @source.indexing_job_id
  end

  test "configuration errors produce an unindexed outcome" do
    error = Embedding::OpenAiEmbeddingService::ConfigurationError.new("bad dimensions")
    job = build_job(embedding_service(error: error))

    assert_no_enqueued_jobs { job.perform_now }

    assert @source.reload.unindexed?
    assert_equal "not_configured", @source.error_code
  end

  private

  def fake_vectors(count)
    Array.new(count) { Array.new(DB_DIMS, 0.25) }
  end

  def embedding_service(vectors: [], configured: true, error: nil, counter: nil)
    Object.new.tap do |service|
      service.define_singleton_method(:configured?) { configured }
      service.define_singleton_method(:model) { "text-embedding-3-small" }
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
    generation = @source.indexing_generation + 1
    job = IndexKnowledgeSourceJob.new(@source.id, generation)
    @source.update_columns(
      status: "pending",
      indexing_generation: generation,
      indexing_job_id: job.job_id,
      indexing_job_execution: 0
    )
    job.define_singleton_method(:embedding_service) { service }
    job
  end
end
