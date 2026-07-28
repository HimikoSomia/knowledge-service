require "zip"

class Extraction::PptxExtractor < Extraction::BaseExtractor
  SLIDE_PATTERN = /^ppt\/slides\/slide(\d+)\.xml$/

  def extract(tempfile)
    sections = []
    raw_parts = []
    slide_data = {}

    Zip::File.open(tempfile.path) do |zip|
      zip.each do |entry|
        match = entry.name.match(SLIDE_PATTERN)
        next unless match

        slide_num = match[1].to_i
        xml = Nokogiri::XML(entry.get_input_stream.read)
        xml.remove_namespaces!

        texts = xml.xpath("//sp//t").map(&:text).reject(&:blank?)
        slide_data[slide_num] = texts unless texts.empty?
      end
    end

    slide_data.keys.sort.each do |slide_num|
      texts = slide_data[slide_num]
      first, *rest = texts

      sections << { "type" => "heading", "level" => 1, "content" => first, "page_number" => slide_num }
      rest.each do |t|
        sections << { "type" => "paragraph", "content" => t, "page_number" => slide_num }
      end
      raw_parts.concat(texts)
    end

    raw_text = raw_parts.join("\n\n")
    metadata = { "extractor" => "pptx", "slide_count" => slide_data.size }
    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
