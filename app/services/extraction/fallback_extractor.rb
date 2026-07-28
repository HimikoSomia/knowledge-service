class Extraction::FallbackExtractor < Extraction::BaseExtractor
  def initialize(content_type: nil)
    @content_type = content_type
  end

  def extract(_tempfile)
    Rails.logger.warn "FallbackExtractor: no extractor available for content_type=#{@content_type.inspect}"
    metadata = { "extractor" => "fallback", "unsupported" => true, "content_type" => @content_type }
    build_result(raw_text: "", sections: [], metadata: metadata)
  end
end
