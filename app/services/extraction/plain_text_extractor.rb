class Extraction::PlainTextExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    text = File.read(tempfile.path, encoding: "UTF-8", invalid: :replace, undef: :replace)
    sections = paragraphs_from_text(text)
    metadata = { "extractor" => "plain_text", "word_count" => text.split.size }
    build_result(raw_text: text, sections: sections, metadata: metadata)
  end
end
