require "test_helper"

class Extraction::ExtractorsTest < ActiveSupport::TestCase
  # --- PlainTextExtractor ---

  test "PlainTextExtractor extracts text and paragraphs" do
    result = extract_with(Extraction::PlainTextExtractor, "sample.txt")
    assert result.raw_text.include?("Hello World")
    assert result.raw_text.include?("first paragraph")
    assert result.sections.any? { |s| s["type"] == "paragraph" }
    assert_equal "plain_text", result.metadata["extractor"]
  end

  # --- CsvExtractor ---

  test "CsvExtractor produces a table section with headers and rows" do
    result = extract_with(Extraction::CsvExtractor, "sample.csv")
    assert_equal 1, result.sections.size
    section = result.sections.first
    assert_equal "table",            section["type"]
    assert_equal %w[name age city],  section["headers"]
    assert_equal 3,                  section["rows"].size
    assert result.raw_text.include?("Alice")
  end

  # --- JsonExtractor ---

  test "JsonExtractor pretty-prints JSON into raw_text" do
    result = extract_with(Extraction::JsonExtractor, "sample.json")
    assert result.raw_text.include?("Alice")
    assert_equal "json", result.metadata["extractor"]
  end

  # --- HtmlExtractor ---

  test "HtmlExtractor extracts headings, paragraphs, lists, and tables" do
    result = extract_with(Extraction::HtmlExtractor, "sample.html")
    types = result.sections.map { |s| s["type"] }.uniq
    assert_includes types, "heading"
    assert_includes types, "paragraph"
    assert_includes types, "list"
    assert_includes types, "table"
    heading = result.sections.find { |s| s["type"] == "heading" && s["level"] == 1 }
    assert_equal "Main Heading", heading["content"]
    assert_equal "html", result.metadata["extractor"]
  end

  # --- FallbackExtractor ---

  test "FallbackExtractor returns empty result with unsupported flag" do
    extractor = Extraction::FallbackExtractor.new(content_type: "application/octet-stream")
    result = extract_with_instance(extractor, "sample.txt")
    assert result.empty?
    assert result.metadata["unsupported"]
    assert_equal "fallback", result.metadata["extractor"]
  end

  # --- DocumentExtractor (factory) ---

  test "DocumentExtractor dispatches plain text blob to PlainTextExtractor" do
    extractor = Extraction::DocumentExtractor.new.for(mock_blob("sample.txt", "text/plain"))
    assert_instance_of Extraction::PlainTextExtractor, extractor
  end

  test "DocumentExtractor dispatches CSV blob to CsvExtractor" do
    extractor = Extraction::DocumentExtractor.new.for(mock_blob("sample.csv", "text/csv"))
    assert_instance_of Extraction::CsvExtractor, extractor
  end

  test "DocumentExtractor dispatches HTML blob to HtmlExtractor" do
    extractor = Extraction::DocumentExtractor.new.for(mock_blob("sample.html", "text/html"))
    assert_instance_of Extraction::HtmlExtractor, extractor
  end

  test "DocumentExtractor falls back for unknown content_type, uses extension" do
    extractor = Extraction::DocumentExtractor.new.for(mock_blob("sample.json", "application/octet-stream"))
    assert_instance_of Extraction::JsonExtractor, extractor
  end

  test "DocumentExtractor returns FallbackExtractor for truly unknown file" do
    extractor = Extraction::DocumentExtractor.new.for(mock_blob("file.xyz", "application/octet-stream"))
    assert_instance_of Extraction::FallbackExtractor, extractor
  end

  private

  def extract_with(extractor_class, fixture_name)
    Tempfile.create([ "test", File.extname(fixture_name) ]) do |tmp|
      tmp.write(File.read(file_fixture(fixture_name)))
      tmp.rewind
      extractor_class.new.extract(tmp)
    end
  end

  def extract_with_instance(extractor, fixture_name)
    Tempfile.create([ "test", File.extname(fixture_name) ]) do |tmp|
      tmp.write(File.read(file_fixture(fixture_name)))
      tmp.rewind
      extractor.extract(tmp)
    end
  end

  # Simple blob double using an anonymous struct — no dependency on Minitest::Mock.
  def mock_blob(filename, content_type)
    Struct.new(:content_type, :filename).new(
      content_type,
      ActiveStorage::Filename.new(filename)
    )
  end
end
