require "test_helper"

class Extraction::ImageExtractorTest < ActiveSupport::TestCase
  setup do
    @extractor = Extraction::ImageExtractor.new
    @original_ocr_new = Extraction::OcrService.method(:new)
  end

  teardown do
    # Remove any singleton override set in a test so other tests are unaffected.
    if Extraction::OcrService.singleton_class.method_defined?(:new, false)
      Extraction::OcrService.singleton_class.remove_method(:new)
    end
  end

  test "returns image_ref section when OCR is unavailable" do
    stub_ocr(available: false, text: "", word_count: 0)

    result = run_extractor
    assert result.sections.any? { |s| s["type"] == "image_ref" }
    assert_equal "ocr_unavailable", result.sections.first["skipped_reason"]
    assert_equal "", result.raw_text
    assert_equal "image", result.metadata["extractor"]
  end

  test "returns image_ref with ocr_unavailable reason when tesseract missing" do
    skip "redundant with above — covered by ocr_unavailable assertion"
  end

  test "returns image_ref when OCR text is below threshold" do
    stub_ocr(available: true, text: "a few words", word_count: 3)

    result = run_extractor
    assert result.sections.any? { |s| s["type"] == "image_ref" }
  end

  test "returns paragraph section with source_type ocr when OCR yields meaningful text" do
    long_text = "word " * 20
    stub_ocr(available: true, text: long_text, word_count: 20)

    result = run_extractor
    para = result.sections.find { |s| s["type"] == "paragraph" }
    assert_not_nil para
    assert_equal "ocr", para["source_type"]
    assert result.raw_text.present?
    assert result.metadata["ocr_applied"]
  end

  private

  def stub_ocr(available:, text:, word_count:, skip_available: false)
    stub_instance = @original_ocr_new.call
    stub_instance.define_singleton_method(:available?) { available }
    stub_instance.define_singleton_method(:ocr) { |_| { text: text, word_count: word_count, available: available } }
    # Adjust skipped_reason expectation: when available? is false and skip_available is true → "ocr_unavailable"
    if skip_available
      stub_instance.define_singleton_method(:available?) { false }
    end
    Extraction::OcrService.define_singleton_method(:new) { stub_instance }
  end

  def run_extractor
    Tempfile.create([ "test_img", ".png" ]) do |tmp|
      tmp.write("fake image content")
      tmp.rewind
      @extractor.extract(tmp)
    end
  end
end
