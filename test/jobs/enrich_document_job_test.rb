require "test_helper"

class EnrichDocumentJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @document = @user.documents.new(title: "Enrich Test")
    @document.file.attach(
      io:           File.open(file_fixture("sample.txt")),
      filename:     "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    @document.update_columns(status: "processed", enrichment_status: "pending")
  end

  test "marks not_applicable when document has no image_ref sections" do
    @document.update_columns(extracted_content: { "sections" => [], "raw_text" => "hello", "metadata" => {} })
    EnrichDocumentJob.perform_now(@document.id)
    assert_equal "not_applicable", @document.reload.enrichment_status
  end

  test "marks not_applicable when vision service is not configured" do
    @document.update_columns(extracted_content: {
      "sections" => [ { "type" => "image_ref", "page_number" => 1, "image_index" => 0 } ],
      "raw_text" => "",
      "metadata" => {}
    })
    # OpenAIVisionService.configured? returns false by default (no OPENAI_API_KEY)
    EnrichDocumentJob.perform_now(@document.id)
    assert_equal "not_applicable", @document.reload.enrichment_status
  end

  test "marks not_applicable when vision service raises NotImplementedError" do
    @document.update_columns(extracted_content: {
      "sections" => [ { "type" => "image_ref", "page_number" => 1, "image_index" => 0 } ],
      "raw_text" => "",
      "metadata" => {}
    })

    original_new = Enrichment::OpenAiVisionService.method(:new)
    stubbed = Object.new
    def stubbed.configured? = true
    def stubbed.describe_image_from_document(_, _) = raise(NotImplementedError, "not ready")

    Enrichment::OpenAiVisionService.define_singleton_method(:new) { stubbed }

    EnrichDocumentJob.perform_now(@document.id)
    assert_equal "not_applicable", @document.reload.enrichment_status
  ensure
    Enrichment::OpenAiVisionService.define_singleton_method(:new, &original_new)
  end

  test "discards job when document does not exist" do
    assert_nothing_raised { EnrichDocumentJob.perform_now(0) }
  end

  test "skips enrichment if already enriched" do
    @document.update_columns(enrichment_status: "enriched")
    # Job should return early without changing status
    EnrichDocumentJob.perform_now(@document.id)
    assert_equal "enriched", @document.reload.enrichment_status
  end
end
