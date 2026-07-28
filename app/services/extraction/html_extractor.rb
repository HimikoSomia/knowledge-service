class Extraction::HtmlExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    raw = File.read(tempfile.path, encoding: "UTF-8", invalid: :replace, undef: :replace)
    doc = Nokogiri::HTML(raw)
    doc.css("script, style, head").remove

    sections = []
    raw_parts = []

    doc.css("h1, h2, h3, h4, h5, h6, p, ul, ol, table").each do |node|
      case node.name
      when /^h(\d)$/
        level = Regexp.last_match(1).to_i
        text = node.text.strip
        next if text.blank?

        sections << { "type" => "heading", "level" => level, "content" => text, "page_number" => nil }
        raw_parts << text
      when "p"
        text = node.text.strip
        next if text.blank?

        sections << { "type" => "paragraph", "content" => text, "page_number" => nil }
        raw_parts << text
      when "ul", "ol"
        items = node.css("li").map { |li| li.text.strip }.reject(&:blank?)
        next if items.empty?

        sections << { "type" => "list", "ordered" => node.name == "ol", "items" => items, "page_number" => nil }
        raw_parts.concat(items)
      when "table"
        headers = node.css("thead th, thead td").map { |th| th.text.strip }
        rows = node.css("tbody tr").map { |tr| tr.css("td, th").map { |td| td.text.strip } }
        next if headers.empty? && rows.empty?

        sections << { "type" => "table", "headers" => headers, "rows" => rows, "page_number" => nil }
        raw_parts << headers.join(" | ") unless headers.empty?
        rows.each { |r| raw_parts << r.join(" | ") }
      end
    end

    raw_text = raw_parts.join("\n\n")
    metadata = { "extractor" => "html", "title" => doc.title, "word_count" => raw_text.split.size }
    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
