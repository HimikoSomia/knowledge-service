require "test_helper"

class ProcessDocumentJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @document = @user.documents.new(title: "Job Test Doc")
    @document.file.attach(
      io:           File.open(file_fixture("sample.txt")),
      filename:     "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    # Reset to pending so job will process
    @document.update_columns(status: "pending", file_checksum: nil)
  end

  test "extracts document, creates chunks, and advances to embedding" do
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document.id, @document.processing_generation ]) do
      ProcessDocumentJob.perform_now(@document.id, @document.processing_generation)
    end
    @document.reload
    assert_equal "embedding", @document.status
    assert @document.chunk_count > 0, "Expected chunk_count > 0"
    assert_not_nil @document.processed_at
    assert_not_nil @document.file_checksum
    assert @document.extracted_content["raw_text"].present?
    assert @document.document_chunks.count > 0
  end

  test "queues image enrichment with an explicit pending outcome" do
    result = Extraction::ExtractionResult.new(
      raw_text: "",
      sections: [
        { "type" => "image_ref", "source_type" => "uploaded", "page_number" => 1, "image_index" => 0 }
      ]
    )
    extractor = Object.new
    extractor.define_singleton_method(:extract) { |_| result }
    job = ProcessDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:extractor_for) { |_| extractor }

    assert_enqueued_with(job: EnrichDocumentJob, args: [ @document.id, @document.processing_generation ]) do
      job.perform_now
    end

    @document.reload
    assert_equal "enriching", @document.status
    assert @document.enrichment_pending?
    assert_nil @document.enriched_at
  end

  test "skips if document already processed with same checksum" do
    checksum = @document.file.blob.checksum
    @document.update_columns(status: "ready", file_checksum: checksum)

    assert_no_difference -> { @document.document_chunks.count } do
      ProcessDocumentJob.perform_now(@document.id, @document.processing_generation)
    end
    assert_equal "ready", @document.reload.status
  end

  test "marks document as failed on extraction error" do
    broken = Object.new
    def broken.for(_blob) = raise(RuntimeError, "boom")
    job = ProcessDocumentJob.new(@document.id, @document.processing_generation)
    job.define_singleton_method(:extractor_for) { |blob| broken.for(blob) }

    job.perform_now

    assert_equal "failed", @document.reload.status
    # Error message is sanitized to a user-friendly string (raw "boom" is in logs only)
    assert @document.error_message.present?
    assert_not_equal "boom", @document.error_message
  end

  test "discards job when document does not exist" do
    # discard_on prevents retrying; job is silently dropped from the queue.
    assert_no_enqueued_jobs do
      assert_nothing_raised { ProcessDocumentJob.perform_now(0) }
    end
  end

  test "duplicate delivery does not extract or enqueue twice" do
    extraction_count = 0
    extractor = Extraction::PlainTextExtractor.new
    first_job = ProcessDocumentJob.new(@document.id, @document.processing_generation)
    second_job = ProcessDocumentJob.new(@document.id, @document.processing_generation)
    [ first_job, second_job ].each do |job|
      job.define_singleton_method(:extractor_for) do |_blob|
        extraction_count += 1
        extractor
      end
    end

    assert_enqueued_jobs 1, only: EmbedDocumentJob do
      first_job.perform_now
      second_job.perform_now
    end

    assert_equal 1, extraction_count
  end

  test "stale extraction results cannot overwrite a newer file generation" do
    original_generation = @document.processing_generation
    delegate = Extraction::PlainTextExtractor.new
    extractor = Object.new
    document = @document
    extractor.define_singleton_method(:extract) do |tempfile|
      document.update_columns(
        processing_generation: original_generation + 1,
        processing_job_id: "replacement-job",
        processing_job_execution: 0,
        status: "pending"
      )
      delegate.extract(tempfile)
    end
    job = ProcessDocumentJob.new(@document.id, original_generation)
    job.define_singleton_method(:extractor_for) { |_blob| extractor }

    assert_no_enqueued_jobs only: [ EnrichDocumentJob, EmbedDocumentJob ] do
      job.perform_now
    end

    @document.reload
    assert_equal original_generation + 1, @document.processing_generation
    assert_equal "pending", @document.status
    assert_empty @document.extracted_content
    assert_empty @document.document_chunks
  end
end
