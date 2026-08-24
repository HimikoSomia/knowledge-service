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
  end

  test "hands existing chunks to embedding when vision is not configured" do
    create_core_chunk
    add_image_ref

    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document.id, @document.processing_generation ]) do
      perform_job(unconfigured_vision_service)
    end

    assert_equal "embedding", @document.reload.status
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
    assert_not_nil @document.enriched_at
    assert_equal 2, @document.document_chunks.count
    assert_equal "A chart showing quarterly growth.", @document.document_chunks.order(:chunk_index).last.content
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

  private

  def add_image_ref
    @document.update_columns(extracted_content: {
      "sections" => [
        { "type" => "image_ref", "source_type" => "uploaded", "page_number" => 1, "image_index" => 0 }
      ],
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
    job = EnrichDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:vision_service) { service }
    job.perform_now
  end
end
