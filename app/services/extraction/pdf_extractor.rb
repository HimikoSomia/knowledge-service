require "pdf-reader"

class Extraction::PdfExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    reader = PDF::Reader.new(tempfile.path)
    sections = []
    raw_parts = []

    reader.pages.each_with_index do |page, idx|
      page_number = idx + 1
      text = page.text.to_s.strip
      next if text.blank?

      raw_parts << text
      paragraphs_from_text(text, page_number: page_number).each do |section|
        sections << section
      end
    end

    raw_text = raw_parts.join("\n\n")
    scanned = raw_text.blank?

    metadata = {
      "extractor"  => "pdf",
      "page_count" => reader.page_count,
      "author"     => reader.info&.fetch(:Author, nil),
      "title"      => reader.info&.fetch(:Title, nil),
      "word_count" => raw_text.split.size,
      "scanned"    => scanned
    }.compact

    if scanned
      # Text extraction yielded nothing — document is likely a scanned PDF.
      # Future enhancement: integrate OCR (e.g. rtesseract) as a fallback here.
      Rails.logger.warn "PdfExtractor: no text extracted from document (possibly scanned). OCR not yet implemented."
    end

    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
