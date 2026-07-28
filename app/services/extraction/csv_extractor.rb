require "csv"

class Extraction::CsvExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    table = CSV.read(tempfile.path, headers: true, encoding: "UTF-8:UTF-8",
                     liberal_parsing: true)
    headers = table.headers.map(&:to_s)
    rows = table.map { |row| row.fields.map(&:to_s) }

    raw_lines = [ headers.join(", ") ] + rows.map { |r| r.join(", ") }
    raw_text = raw_lines.join("\n")

    sections = [ { "type" => "table", "headers" => headers, "rows" => rows, "page_number" => nil } ]
    metadata = { "extractor" => "csv", "row_count" => rows.size, "column_count" => headers.size }
    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
