require "test_helper"

class Chunking::DocumentChunkerTest < ActiveSupport::TestCase
  setup do
    @user     = users(:one)
    @document = @user.documents.new(title: "Chunker Test")
    @document.file.attach(
      io:           File.open(file_fixture("sample.txt")),
      filename:     "sample.txt",
      content_type: "text/plain"
    )
    @document.save!
    @document.update_columns(status: "processing")
  end

  test "chunk! creates DocumentChunk records from extraction result" do
    result = Extraction::ExtractionResult.new(
      raw_text: "Hello world.\n\nSecond paragraph here.",
      sections: [
        { "type" => "heading",   "level" => 1, "content" => "Title",              "page_number" => 1 },
        { "type" => "paragraph", "content" => "Hello world.",                    "page_number" => 1 },
        { "type" => "paragraph", "content" => "Second paragraph here.",           "page_number" => 1 }
      ]
    )

    count = Chunking::DocumentChunker.new(@document, result).chunk!
    assert count > 0
    assert_equal count, @document.document_chunks.count

    chunks = @document.document_chunks.order(:chunk_index)
    assert_equal 0, chunks.first.chunk_index
    chunks.each { |c| assert c.content.present? }
  end

  test "chunk! is idempotent — replaces existing chunks on re-run" do
    result = Extraction::ExtractionResult.new(
      raw_text: "Some text.",
      sections: [ { "type" => "paragraph", "content" => "Some text.", "page_number" => nil } ]
    )

    Chunking::DocumentChunker.new(@document, result).chunk!
    first_count = @document.document_chunks.count

    Chunking::DocumentChunker.new(@document, result).chunk!
    assert_equal first_count, @document.document_chunks.count
  end

  test "chunk! returns 0 and leaves no chunks for empty extraction result" do
    result = Extraction::ExtractionResult.new(raw_text: "", sections: [])
    count = Chunking::DocumentChunker.new(@document, result).chunk!
    assert_equal 0, count
    assert_equal 0, @document.document_chunks.count
  end

  test "chunk! stores page_number on chunks when available" do
    result = Extraction::ExtractionResult.new(
      raw_text: "Page one content.",
      sections: [ { "type" => "paragraph", "content" => "Page one content.", "page_number" => 3 } ]
    )
    Chunking::DocumentChunker.new(@document, result).chunk!
    assert_equal 3, @document.document_chunks.first.page_number
  end

  test "chunk! splits oversized paragraphs into multiple chunks" do
    long_text = ("word " * 600).strip # ~3000 chars, exceeds MAX_CHARS=2000
    result = Extraction::ExtractionResult.new(
      raw_text: long_text,
      sections: [ { "type" => "paragraph", "content" => long_text, "page_number" => nil } ]
    )
    count = Chunking::DocumentChunker.new(@document, result).chunk!
    assert count > 1, "Expected long paragraph to be split into multiple chunks"
  end

  test "chunk! stores table section correctly" do
    result = Extraction::ExtractionResult.new(
      raw_text: "Name | Age\nAlice | 30",
      sections: [
        {
          "type"    => "table",
          "headers" => %w[Name Age],
          "rows"    => [ %w[Alice 30] ],
          "page_number" => nil
        }
      ]
    )
    Chunking::DocumentChunker.new(@document, result).chunk!
    chunk = @document.document_chunks.first
    assert_equal "table", chunk.metadata["type"]
    assert chunk.content.include?("Name")
    assert chunk.content.include?("Alice")
  end
end
