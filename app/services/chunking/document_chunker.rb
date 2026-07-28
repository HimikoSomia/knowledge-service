class Chunking::DocumentChunker
  MAX_CHARS  = 2000
  OVERLAP_CHARS = 100

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
        document_id: @document.id,
        chunk_index:  index,
        content:      chunk[:content],
        page_number:  chunk[:page_number],
        start_char:   chunk[:start_char],
        end_char:     chunk[:end_char],
        metadata:     chunk[:metadata],
        created_at:   now,
        updated_at:   now
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
        split_text(text).each do |part|
          chunks << build_chunk(part, section, char_offset, current_heading, "paragraph")
          char_offset += part.length
        end

      when "table"
        text = table_to_text(section)
        split_text(text).each do |part|
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

  # Splits text into sentence-aware segments no longer than MAX_CHARS.
  # Falls back to word-boundary splitting when sentences are too long.
  def split_text(text)
    return [ text ] if text.length <= MAX_CHARS

    parts     = []
    sentences = text.scan(/[^.!?\n]+(?:[.!?\n]+|$)/).map(&:strip).reject(&:empty?)
    current   = ""

    sentences.each do |sentence|
      if sentence.length > MAX_CHARS
        # Sentence itself is oversized — flush current and split by words
        parts << current.strip unless current.blank?
        current = ""
        parts.concat(split_by_words(sentence))
        next
      end

      if current.length + sentence.length + 1 > MAX_CHARS
        parts  << current.strip unless current.blank?
        current = sentence
      else
        current = current.empty? ? sentence : "#{current} #{sentence}"
      end
    end

    parts << current.strip unless current.blank?
    parts.empty? ? [ text[0, MAX_CHARS] ] : parts
  end

  # Word-boundary splitting for text without sentence markers.
  def split_by_words(text)
    parts   = []
    current = ""

    text.split.each do |word|
      if current.length + word.length + 1 > MAX_CHARS
        parts  << current.strip unless current.blank?
        current = word
      else
        current = current.empty? ? word : "#{current} #{word}"
      end
    end

    parts << current.strip unless current.blank?
    parts.empty? ? [ text[0, MAX_CHARS] ] : parts
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
end
