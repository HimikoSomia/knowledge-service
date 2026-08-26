require "application_system_test_case"

class DocumentRetriesTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @document = documents(:pending_doc)
    @document.file.attach(
      io: File.open(file_fixture("sample.txt")),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    clear_enqueued_jobs
    @document.update_columns(status: "failed", error_message: "Processing could not be completed.")
    sign_in_through_browser_as(@user)
  end

  test "retries failed document processing from the document page" do
    visit document_path(@document)

    assert_text "Document processing failed"
    click_button "Retry processing"

    assert_text "Document processing was queued again."
    assert @document.reload.pending?
    assert_enqueued_jobs 1, only: ProcessDocumentJob
  end
end
