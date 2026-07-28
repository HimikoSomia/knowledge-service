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

  test "processes document and creates chunks" do
    ProcessDocumentJob.perform_now(@document.id)
    @document.reload
    assert_equal "processed", @document.status
    assert @document.chunk_count > 0, "Expected chunk_count > 0"
    assert_not_nil @document.processed_at
    assert_not_nil @document.file_checksum
    assert @document.extracted_content["raw_text"].present?
    assert @document.document_chunks.count > 0
  end

  test "skips if document already processed with same checksum" do
    checksum = @document.file.blob.checksum
    @document.update_columns(status: "processed", file_checksum: checksum)

    assert_no_difference -> { @document.document_chunks.count } do
      ProcessDocumentJob.perform_now(@document.id)
    end
    # status should remain processed, not re-set to processing
    assert_equal "processed", @document.reload.status
  end

  test "marks document as failed on extraction error" do
    original_new = Extraction::DocumentExtractor.method(:new)
    broken = Object.new
    def broken.for(_blob) = raise(RuntimeError, "boom")
    Extraction::DocumentExtractor.define_singleton_method(:new) { broken }

    ProcessDocumentJob.perform_now(@document.id)

    assert_equal "failed", @document.reload.status
    assert_equal "boom",   @document.error_message
  ensure
    Extraction::DocumentExtractor.define_singleton_method(:new, &original_new)
  end

  test "discards job when document does not exist" do
    # discard_on prevents retrying; job is silently dropped from the queue.
    assert_nothing_raised { ProcessDocumentJob.perform_now(0) }
  end
end
