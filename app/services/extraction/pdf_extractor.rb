require "pdf-reader"

class Extraction::PdfExtractor < Extraction::BaseExtractor
  # Pages with fewer words than this are treated as sparse (likely scanned or image-only).
  TEXT_DENSITY_THRESHOLD = 30

  # Section-number patterns that identify a paragraph as a heading.
  HEADING_PATTERNS = [
    /\A\d+(\.\d+)*\.\s+\S/,   # 1.  1.1  1.1.1
    /\A[IVX]+\.\s+[A-Z]/,     # I.  II.  III.
    /\A[#]{1,6}\s+\S/,         # #  ##  ###  (Markdown)
    /\AChapter\s+\d+/i,        # Chapter 3
    /\AAppendix\s+[A-Z0-9]/i   # Appendix A
  ].freeze

  def extract(tempfile)
    reader = PDF::Reader.new(tempfile.path)
    sections = []
    raw_parts = []
    page_word_counts = []
    sparse_pages = []

    reader.pages.each_with_index do |page, idx|
      page_number = idx + 1
      text = page.text.to_s.strip
      word_count = text.split.size
      page_word_counts << word_count

      if word_count >= TEXT_DENSITY_THRESHOLD
        raw_parts << text
        sections_from_page_text(text, page_number).each { |s| sections << s }
      else
        sparse_pages << page_number
        Rails.logger.info "PdfExtractor: page #{page_number} is sparse (#{word_count} words), attempting image extraction"
        image_sections = extract_page_images(tempfile.path, page_number)
        sections.concat(image_sections)
        image_sections.each { |s| raw_parts << s["content"] if s["content"].present? }
      end
    end

    raw_text = raw_parts.join("\n\n")
    total_words = raw_text.split.size
    density_ratio = reader.page_count > 0 ? (total_words.to_f / reader.page_count).round(1) : 0.0

    metadata = {
      "extractor"          => "pdf",
      "page_count"         => reader.page_count,
      "author"             => reader.info&.fetch(:Author, nil),
      "title"              => reader.info&.fetch(:Title, nil),
      "word_count"         => total_words,
      "scanned"            => raw_text.blank?,
      "sparse_pages"       => sparse_pages.any? ? sparse_pages : nil,
      "text_density_ratio" => density_ratio
    }.compact

    if raw_text.blank?
      Rails.logger.warn "PdfExtractor: no text extracted — document may be fully scanned"
    end

    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end

  private

  # Splits a page's text into heading and paragraph sections using heuristics.
  def sections_from_page_text(text, page_number)
    text.split(/\n{2,}/).map(&:strip).reject(&:empty?).map do |para|
      lines = para.split("\n").map(&:strip).reject(&:empty?)
      if lines.size == 1 && heading_line?(lines.first)
        { "type"        => "heading",
          "level"       => heading_level(lines.first),
          "content"     => lines.first,
          "page_number" => page_number }
      else
        { "type" => "paragraph", "content" => para, "page_number" => page_number }
      end
    end
  end

  # Attempts image/OCR extraction for a sparse page.
  # Returns an array of paragraph or image_ref sections.
  def extract_page_images(pdf_path, page_number)
    image_extractor = Extraction::PdfImageExtractor.new
    return [] unless image_extractor.available?

    image_extractor.extract_from_page(pdf_path, page_number: page_number)
  rescue => e
    Rails.logger.error "PdfExtractor: image extraction failed for page #{page_number}: #{e.message}"
    []
  end

  def heading_line?(line)
    return false if line.blank? || line.length > 120

    return true if HEADING_PATTERNS.any? { |pat| line.match?(pat) } && line.length < 100

    # ALL CAPS: at least 2 words, all uppercase alpha characters, short line
    words = line.gsub(/[^a-zA-Z0-9\s]/, " ").split.reject(&:empty?)
    words.size.between?(2, 12) &&
      words.all? { |w| w == w.upcase && w.match?(/[A-Z]/) } &&
      line.length <= 80
  end

  def heading_level(line)
    return line[/\A([#]+)/, 1].length.clamp(1, 3) if line.match?(/\A[#]+\s/)
    return 3 if line.match?(/\A\d+\.\d+\.\d+\s/)
    return 2 if line.match?(/\A\d+\.\d+\s/)
    return 1 if line.match?(/\A\d+\.\s/)
    return 1 if line.match?(/\A[IVX]+\.\s/)
    1
  end
end

