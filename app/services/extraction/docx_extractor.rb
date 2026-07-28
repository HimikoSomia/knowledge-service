require "docx"

class Extraction::DocxExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    doc = Docx::Document.open(tempfile.path)
    sections = []
    raw_parts = []

    doc.paragraphs.each do |para|
      text = para.to_s.strip
      next if text.blank?

      style = para.respond_to?(:style) ? para.style.to_s.downcase : ""
      if style.start_with?("heading")
        level = style.match(/(\d+)/)&.captures&.first&.to_i || 1
        sections << { "type" => "heading", "level" => level, "content" => text, "page_number" => nil }
      else
        sections << { "type" => "paragraph", "content" => text, "page_number" => nil }
      end
      raw_parts << text
    end

    doc.tables.each do |table|
      headers = table.rows.first&.cells&.map { |c| c.to_s.strip } || []
      rows = table.rows.drop(1).map { |row| row.cells.map { |c| c.to_s.strip } }
      sections << { "type" => "table", "headers" => headers, "rows" => rows, "page_number" => nil }
      raw_parts << headers.join(" | ") unless headers.empty?
      rows.each { |r| raw_parts << r.join(" | ") }
    end

    raw_text = raw_parts.join("\n\n")
    metadata = { "extractor" => "docx", "word_count" => raw_text.split.size }
    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
