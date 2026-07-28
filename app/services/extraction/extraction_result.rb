class Extraction::ExtractionResult
  attr_reader :raw_text, :sections, :metadata

  def initialize(raw_text:, sections:, metadata: {})
    @raw_text = raw_text.to_s
    @sections = Array(sections)
    @metadata = metadata.to_h
  end

  def empty?
    raw_text.blank? && sections.empty?
  end

  # Returns a plain Hash with string keys suitable for JSONB storage.
  def to_h
    {
      "raw_text" => raw_text,
      "metadata" => metadata,
      "sections" => sections
    }
  end
end
