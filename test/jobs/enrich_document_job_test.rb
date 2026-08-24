require "test_helper"

class EnrichDocumentJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @document = @user.documents.new(title: "Enrich Test")
    @document.file.attach(
      io: File.open(file_fixture("sample.txt")),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    @document.update_columns(status: "enriching", processed_at: Time.current)
  end

  test "completes processing when there are no image refs or chunks" do
    @document.update_columns(extracted_content: { "sections" => [], "raw_text" => "", "metadata" => {} })

    assert_no_enqueued_jobs only: EmbedDocumentJob do
      perform_job(unconfigured_vision_service)
    end

    assert_equal "processed", @document.reload.status
    assert @document.enrichment_not_required?
    assert_nil @document.enriched_at
  end

  test "hands existing chunks to embedding when vision is not configured" do
    create_core_chunk
    add_image_ref

    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document.id, @document.processing_generation ]) do
      perform_job(unconfigured_vision_service)
    end

    assert_equal "embedding", @document.reload.status
    assert @document.enrichment_skipped?
    assert_not_nil @document.enriched_at
    assert_equal "skipped", image_enrichment(0)["status"]
    assert_equal "not_configured", image_enrichment(0)["error_code"]
  end

  test "stores image descriptions before handing the document to embedding" do
    create_core_chunk
    add_image_ref
    vision = Object.new
    def vision.configured? = true
    def vision.describe_image_from_document(_, _) = "A chart showing quarterly growth."

    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document.id, @document.processing_generation ]) do
      perform_job(vision)
    end

    @document.reload
    assert_equal "embedding", @document.status
    assert @document.enrichment_succeeded?
    assert_not_nil @document.enriched_at
    assert_equal 2, @document.document_chunks.count
    assert_equal "A chart showing quarterly growth.", @document.document_chunks.order(:chunk_index).last.content
    assert_equal "succeeded", image_enrichment(0)["status"]
  end

  test "skips a document that is already ready" do
    @document.update_columns(status: "ready")

    assert_no_enqueued_jobs do
      perform_job(unconfigured_vision_service)
    end

    assert_equal "ready", @document.reload.status
  end

  test "discards job when document does not exist" do
    assert_no_enqueued_jobs do
      assert_nothing_raised { EnrichDocumentJob.perform_now(0) }
    end
  end

  test "retry upserts an image description instead of duplicating it" do
    create_core_chunk
    add_image_ref
    vision = Object.new
    def vision.configured? = true
    def vision.describe_image_from_document(_, _) = "A chart showing quarterly growth."

    job = EnrichDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:vision_service) { vision }
    handoff_attempts = 0
    job.define_singleton_method(:continue_to_embedding) do |*args, **kwargs|
      handoff_attempts += 1
      raise "handoff interrupted" if handoff_attempts == 1

      super(*args, **kwargs)
    end

    assert_enqueued_jobs 1, only: EnrichDocumentJob do
      job.perform_now
    end
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      job.perform_now
    end

    descriptions = @document.document_chunks.where(source_key: "image_ref:0")
    assert_equal 1, descriptions.count
    assert_equal 2, @document.document_chunks.count
  end

  test "records one permanent image failure and continues with partial success" do
    create_core_chunk
    add_image_refs(2)
    vision = Object.new
    def vision.configured? = true
    def vision.describe_image_from_document(_, image_ref)
      if image_ref["image_index"].zero?
        "A successfully described chart."
      else
        raise Enrichment::OpenAiVisionService::PermanentImageError.new(
          "rejected",
          code: "provider_rejected_image"
        )
      end
    end

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      perform_job(vision)
    end

    @document.reload
    assert @document.enrichment_partial?
    assert_not_nil @document.enriched_at
    assert_equal "succeeded", image_enrichment(0)["status"]
    assert_equal "failed", image_enrichment(1)["status"]
    assert_equal "provider_rejected_image", image_enrichment(1)["error_code"]
    assert_equal 2, @document.document_chunks.count
  end

  test "retries a transient provider failure without recording false completion" do
    create_core_chunk
    add_image_ref
    vision = failing_vision_service(Enrichment::OpenAiVisionService::TransientError.new("timeout"))

    assert_enqueued_jobs 1, only: EnrichDocumentJob do
      perform_job(vision)
    end

    @document.reload
    assert_equal "failed", @document.status
    assert @document.enrichment_in_progress?
    assert_nil @document.enriched_at
    assert_nil image_enrichment(0)
  end

  test "marks enrichment failed but preserves extracted text after retries are exhausted" do
    create_core_chunk
    add_image_ref
    vision = failing_vision_service(Enrichment::OpenAiVisionService::TransientError.new("timeout"))
    job = build_job(vision)
    job.exception_executions[[ Enrichment::OpenAiVisionService::TransientError ].to_s] = 2

    assert_no_enqueued_jobs do
      assert_nothing_raised { job.perform_now }
    end

    @document.reload
    assert_equal "processed", @document.status
    assert @document.enrichment_failed?
    assert_not_nil @document.enriched_at
    assert_equal "Existing text", @document.document_chunks.first.content
    assert_equal 1, @document.document_chunks.count
    assert_equal "image_ref", @document.extracted_content.dig("sections", 0, "type")
  end

  test "all permanent image failures leave the document processed without embedding" do
    create_core_chunk
    add_image_ref
    error = Enrichment::OpenAiVisionService::PermanentImageError.new("rejected", code: "provider_rejected_image")

    assert_no_enqueued_jobs only: EmbedDocumentJob do
      perform_job(failing_vision_service(error))
    end

    @document.reload
    assert_equal "processed", @document.status
    assert @document.enrichment_failed?
    assert_equal "failed", image_enrichment(0)["status"]
    assert_equal 1, @document.document_chunks.count
  end

  test "provider authentication failure ends enrichment without retrying" do
    create_core_chunk
    add_image_ref
    error = Enrichment::OpenAiVisionService::ConfigurationError.new("invalid credentials")

    assert_no_enqueued_jobs do
      assert_nothing_raised { perform_job(failing_vision_service(error)) }
    end

    @document.reload
    assert_equal "processed", @document.status
    assert @document.enrichment_failed?
    assert_not_nil @document.enriched_at
    assert_nil @document.error_message
  end

  test "retry preserves completed image outcome when embedding enqueue fails" do
    create_core_chunk
    add_image_ref
    description_calls = 0
    vision = Object.new
    vision.define_singleton_method(:configured?) { true }
    vision.define_singleton_method(:describe_image_from_document) do |_, _|
      description_calls += 1
      "A completed image description."
    end
    unavailable_embedding_job = Object.new
    unavailable_embedding_job.define_singleton_method(:job_id) { "unavailable-embedding-job" }
    unavailable_embedding_job.define_singleton_method(:enqueue) { raise "queue unavailable" }
    job = build_job(vision)

    assert_enqueued_jobs 1, only: EnrichDocumentJob do
      with_stubbed_embedding_job(unavailable_embedding_job) { job.perform_now }
    end
    clear_enqueued_jobs

    @document.reload
    assert_equal job.job_id, @document.processing_job_id
    assert @document.enrichment_succeeded?

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      job.perform_now
    end

    assert_equal 1, description_calls
    assert @document.reload.enrichment_succeeded?
    assert_equal 1, @document.document_chunks.where(source_key: "image_ref:0").count
  end

  private

  def add_image_ref
    add_image_refs(1)
  end

  def add_image_refs(count)
    @document.update_columns(extracted_content: {
      "sections" => Array.new(count) do |index|
        { "type" => "image_ref", "source_type" => "uploaded", "page_number" => 1, "image_index" => index }
      end,
      "raw_text" => "",
      "metadata" => {}
    })
  end

  def create_core_chunk
    @document.document_chunks.create!(chunk_index: 0, content: "Existing text", metadata: {})
    @document.update_columns(chunk_count: 1)
  end

  def unconfigured_vision_service
    Object.new.tap do |service|
      service.define_singleton_method(:configured?) { false }
    end
  end

  def perform_job(service)
    build_job(service).perform_now
  end

  def build_job(service)
    job = EnrichDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:vision_service) { service }
    job
  end

  def failing_vision_service(error)
    Object.new.tap do |service|
      service.define_singleton_method(:configured?) { true }
      service.define_singleton_method(:describe_image_from_document) { |_, _| raise error }
    end
  end

  def image_enrichment(index)
    @document.reload.extracted_content.dig("sections", index, "enrichment")
  end

  def with_stubbed_embedding_job(job)
    EmbedDocumentJob.define_singleton_method(:new) { |*| job }
    yield
  ensure
    EmbedDocumentJob.singleton_class.remove_method(:new)
  end
end
