require "test_helper"

class Extraction::OcrServiceTest < ActiveSupport::TestCase
  setup do
    @service = Extraction::OcrService.new
  end

  test "available? returns a boolean" do
    assert_includes [ true, false ], @service.available?
  end

  test "meaningful? returns false for low word counts" do
    assert_not @service.meaningful?({ word_count: 0 })
    assert_not @service.meaningful?({ word_count: 5 })
    assert_not @service.meaningful?({ word_count: Extraction::OcrService::MIN_WORD_COUNT - 1 })
  end

  test "meaningful? returns true at or above threshold" do
    assert @service.meaningful?({ word_count: Extraction::OcrService::MIN_WORD_COUNT })
    assert @service.meaningful?({ word_count: 100 })
  end

  test "ocr returns available: false when tesseract not installed" do
    @service.instance_variable_set(:@available_cache, false)
    result = @service.ocr(file_fixture("sample.txt"))
    assert_equal false, result[:available]
    assert_equal "", result[:text]
    assert_equal 0, result[:word_count]
  end

  test "ocr runs successfully when tesseract is available" do
    skip "Tesseract not installed" unless @service.available?
    result = @service.ocr(file_fixture("sample.txt"))
    assert result[:available]
    assert_kind_of String, result[:text]
    assert_kind_of Integer, result[:word_count]
  end
end
