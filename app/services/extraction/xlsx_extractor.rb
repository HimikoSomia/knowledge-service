require "roo"

class Extraction::XlsxExtractor < Extraction::BaseExtractor
  def extract(tempfile)
    spreadsheet = Roo::Spreadsheet.open(tempfile.path)
    sections = []
    raw_parts = []

    spreadsheet.sheets.each do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      last_row = sheet.last_row
      next if last_row.nil?

      headers = sheet.row(1).map { |v| v.to_s.strip }
      rows = last_row >= 2 ? (2..last_row).map { |r| sheet.row(r).map { |v| v.to_s.strip } } : []

      sections << {
        type: "table",
        sheet_name: sheet_name,
        headers: headers,
        rows: rows,
        page_number: nil
      }

      raw_parts << "Sheet: #{sheet_name}"
      raw_parts << headers.join(", ")
      rows.each { |r| raw_parts << r.join(", ") }
    end

    raw_text = raw_parts.join("\n")
    metadata = { "extractor" => "xlsx", "sheet_count" => spreadsheet.sheets.size }
    build_result(raw_text: raw_text, sections: sections, metadata: metadata)
  end
end
