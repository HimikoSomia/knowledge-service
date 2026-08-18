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
    assert_enqueued_with(job: EmbedDocumentJob, args: [ @document.id ]) do
      ProcessDocumentJob.perform_now(@document.id)
    end
    @document.reload
    assert_equal "embedding", @document.status
    assert @document.chunk_count > 0, "Expected chunk_count > 0"
    assert_not_nil @document.processed_at
    assert_not_nil @document.file_checksum
    assert @document.extracted_content["raw_text"].present?
    assert @document.document_chunks.count > 0
  end

  test "skips if document already processed with same checksum" do
    checksum = @document.file.blob.checksum
    @document.update_columns(status: "ready", file_checksum: checksum)

    assert_no_difference -> { @document.document_chunks.count } do
      ProcessDocumentJob.perform_now(@document.id)
    end
    assert_equal "ready", @document.reload.status
  end

  test "marks document as failed on extraction error" do
    broken = Object.new
    def broken.for(_blob) = raise(RuntimeError, "boom")
    job = ProcessDocumentJob.new(@document.id)
    job.define_singleton_method(:extractor_for) { |blob| broken.for(blob) }

    job.perform_now

    assert_equal "failed", @document.reload.status
    # Error message is sanitized to a user-friendly string (raw "boom" is in logs only)
    assert @document.error_message.present?
    assert_not_equal "boom", @document.error_message
  end

  test "discards job when document does not exist" do
    # discard_on prevents retrying; job is silently dropped from the queue.
    assert_nothing_raised { ProcessDocumentJob.perform_now(0) }
  end
end
