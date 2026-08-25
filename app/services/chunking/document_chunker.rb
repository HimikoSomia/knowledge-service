require "digest"

class Chunking::DocumentChunker
  MAX_CHARS = Chunking::TextSplitter::MAX_CHARS

  def initialize(document, extraction_result)
    @document = document
    @result   = extraction_result
  end

  # Deletes existing chunks, builds new ones from the extraction result,
  # inserts them in bulk, and returns the number of chunks created.
  def chunk!
    # Delete via the model directly to avoid caching the association as empty,
    # which would hide the subsequently inserted rows from the association proxy.
    DocumentChunk.where(document_id: @document.id).delete_all
    chunks = build_chunks
    return 0 if chunks.empty?

    now = Time.current
    records = chunks.each_with_index.map do |chunk, index|
      {
        document_id:      @document.id,
        chunk_index:       index,
        content:           chunk[:content],
        content_checksum:  content_checksum(chunk[:content]),
        token_count:       estimate_tokens(chunk[:content]),
        page_number:       chunk[:page_number],
        start_char:        chunk[:start_char],
        end_char:          chunk[:end_char],
        metadata:          chunk[:metadata],
        created_at:        now,
        updated_at:        now
      }
    end

    DocumentChunk.insert_all!(records)
    chunks.size
  end

  private

  def build_chunks
    chunks = []
    char_offset = 0
    current_heading = nil

    @result.sections.each do |section|
      type = section["type"]

      case type
      when "heading"
        level   = section["level"].to_i
        content = section["content"].to_s
        current_heading = { "level" => level, "content" => content }
        # Short headings are folded into the next paragraph rather than
        # becoming standalone chunks unless they are very long.
        if content.length > MAX_CHARS
          chunks << build_chunk(content, section, char_offset, current_heading, "heading")
          char_offset += content.length
        end

      when "paragraph"
        text = section["content"].to_s
        text_splitter.split(text).each do |part|
          chunks << build_chunk(part, section, char_offset, current_heading, "paragraph")
          char_offset += part.length
        end

      when "table"
        text = table_to_text(section)
        text_splitter.split(text).each do |part|
          meta = { "type" => "table", "heading" => current_heading,
                   "headers" => section["headers"] }.compact
          chunks << {
            content:     part,
            page_number: section["page_number"],
            start_char:  char_offset,
            end_char:    char_offset + part.length,
            metadata:    meta
          }
          char_offset += part.length
        end

      when "list"
        items = section["items"].to_a
        text  = items.join("\n")
        meta  = { "type" => "list",
                  "ordered" => section["ordered"],
                  "heading" => current_heading }.compact
        chunks << {
          content:     text,
          page_number: section["page_number"],
          start_char:  char_offset,
          end_char:    char_offset + text.length,
          metadata:    meta
        }
        char_offset += text.length

      when "image_ref"
        # image_ref sections without OCR text do not produce chunks in the core pipeline.
        # They are preserved in extracted_content for optional enrichment by EnrichDocumentJob.
        next
      end
    end

    chunks
  end

  def build_chunk(text, section, offset, heading, type)
    {
      content:     text,
      page_number: section["page_number"],
      start_char:  offset,
      end_char:    offset + text.length,
      metadata:    { "type" => type, "heading" => heading, "source_type" => section["source_type"] }.compact
    }
  end

  def table_to_text(section)
    headers = section["headers"].to_a
    rows    = section["rows"].to_a
    lines   = []
    lines << headers.join(" | ") if headers.any?
    lines << ("-" * 40) if headers.any?
    rows.each { |row| lines << Array(row).join(" | ") }
    lines.join("\n")
  end

  # Short (16-char) SHA-256 prefix used to detect content changes for idempotent
  # re-embedding. Not a security hash — collision probability is negligible for
  # this use case.
  def content_checksum(text)
    Digest::SHA256.hexdigest(text.to_s)[0, 16]
  end

  # Rough token-count estimate: 1 token ≈ 4 characters for English text.
  # Used to pre-check token budget and populate the token_count column.
  # Replace with tiktoken if accurate counts are needed.
  def estimate_tokens(text)
    (text.to_s.bytesize / 4.0).ceil
  end

  def text_splitter
    @text_splitter ||= Chunking::TextSplitter.new(max_chars: MAX_CHARS)
  end
end
