class Extraction::BaseExtractor
  # Subclasses implement #extract(tempfile) → Extraction::ExtractionResult
  def extract(_tempfile)
    raise NotImplementedError, "#{self.class}#extract is not implemented"
  end

  protected

  def build_result(raw_text:, sections:, metadata: {})
    Extraction::ExtractionResult.new(raw_text: raw_text, sections: sections, metadata: metadata)
  end

  # Splits a plain text string into paragraph-level section hashes (string keys).
  def paragraphs_from_text(text, page_number: nil)
    text.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?).map do |para|
      { "type" => "paragraph", "content" => para, "page_number" => page_number }
    end
  end
end
