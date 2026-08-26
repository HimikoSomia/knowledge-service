require "test_helper"

class DocumentRetriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @document = documents(:pending_doc)
    @document.file.attach(
      io: File.open(file_fixture("sample.txt")),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    clear_enqueued_jobs
    @document.update_columns(status: "failed", error_message: "Safe processing failure")
    sign_in_as(@user)
  end

  test "owner can retry a failed document" do
    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      post document_retry_path(@document)
    end

    assert_redirected_to document_path(@document)
    assert @document.reload.pending?
    assert_nil @document.error_message
  end

  test "owner can retry a failed document through JSON" do
    post document_retry_path(@document), as: :json

    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]
    assert_nil response.parsed_body["error_message"]
  end

  test "does not retry a document that is not failed" do
    @document.update_columns(status: "ready")

    assert_no_enqueued_jobs do
      post document_retry_path(@document), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "not_retryable", response.parsed_body["error"]
  end

  test "cannot retry another user's document" do
    other_document = documents(:failed_doc)

    assert_no_enqueued_jobs do
      post document_retry_path(other_document), as: :json
    end

    assert_response :not_found
    assert other_document.reload.failed?
  end

  test "requires authentication" do
    sign_out

    assert_no_enqueued_jobs do
      post document_retry_path(@document)
    end

    assert_redirected_to new_session_path
    assert @document.reload.failed?
  end

  test "a repeated retry request does not queue a second job" do
    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      post document_retry_path(@document), as: :json
      assert_response :accepted

      post document_retry_path(@document), as: :json
      assert_response :unprocessable_entity
    end
  end

  test "records queue failure when retry cannot be enqueued" do
    unavailable_job = Object.new
    unavailable_job.define_singleton_method(:job_id) { "unavailable-document-job" }
    unavailable_job.define_singleton_method(:enqueue) { raise "queue unavailable" }

    with_stubbed_processing_job(unavailable_job) do
      post document_retry_path(@document), as: :json
    end

    assert_response :service_unavailable
    assert @document.reload.failed?
    assert_equal "Document processing could not be queued. Please try again.", @document.error_message
  end

  private

  def with_stubbed_processing_job(job)
    ProcessDocumentJob.define_singleton_method(:new) { |*| job }
    yield
  ensure
    ProcessDocumentJob.singleton_class.remove_method(:new)
  end
end
