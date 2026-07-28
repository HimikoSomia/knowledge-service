class Extraction::JsonExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    raw = File.read(tempfile.path, encoding: "UTF-8", invalid: :replace, undef: :replace)
    parsed = JSON.parse(raw)
    pretty = JSON.pretty_generate(parsed)
    sections = [ { "type" => "paragraph", "content" => pretty, "page_number" => nil } ]
    metadata = { "extractor" => "json" }
    build_result(raw_text: pretty, sections: sections, metadata: metadata)
  rescue JSON::ParserError => e
    metadata = { "extractor" => "json", "parse_error" => e.message }
    build_result(raw_text: raw.to_s, sections: [], metadata: metadata)
  end
end
