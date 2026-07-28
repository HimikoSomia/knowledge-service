class Extraction::DocumentExtractor
  CONTENT_TYPE_MAP = {
    "text/plain"          => Extraction::PlainTextExtractor,
    "text/markdown"       => Extraction::PlainTextExtractor,
    "text/csv"            => Extraction::CsvExtractor,
    "application/json"    => Extraction::JsonExtractor,
    "text/html"           => Extraction::HtmlExtractor,
    "application/xhtml+xml" => Extraction::HtmlExtractor,
    "application/xml"     => Extraction::HtmlExtractor,
    "text/xml"            => Extraction::HtmlExtractor,
    "application/pdf"     => Extraction::PdfExtractor,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => Extraction::DocxExtractor,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"       => Extraction::XlsxExtractor,
    "application/vnd.ms-excel"                                                 => Extraction::XlsxExtractor,
    "application/vnd.oasis.opendocument.spreadsheet"                           => Extraction::XlsxExtractor,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => Extraction::PptxExtractor
  }.freeze

  EXTENSION_MAP = {
    "txt"      => Extraction::PlainTextExtractor,
    "md"       => Extraction::PlainTextExtractor,
    "markdown" => Extraction::PlainTextExtractor,
    "csv"      => Extraction::CsvExtractor,
    "json"     => Extraction::JsonExtractor,
    "html"     => Extraction::HtmlExtractor,
    "htm"      => Extraction::HtmlExtractor,
    "xml"      => Extraction::HtmlExtractor,
    "pdf"      => Extraction::PdfExtractor,
    "docx"     => Extraction::DocxExtractor,
    "xlsx"     => Extraction::XlsxExtractor,
    "xls"      => Extraction::XlsxExtractor,
    "ods"      => Extraction::XlsxExtractor,
    "pptx"     => Extraction::PptxExtractor
  }.freeze

  # Returns an extractor instance appropriate for the given Active Storage blob.
  def for(blob)
    extractor_class = CONTENT_TYPE_MAP[blob.content_type]
    extractor_class ||= EXTENSION_MAP[file_extension(blob)]

    if extractor_class
      extractor_class.new
    else
      Extraction::FallbackExtractor.new(content_type: blob.content_type)
    end
  end

  private

  def file_extension(blob)
    File.extname(blob.filename.to_s).delete_prefix(".").downcase
  end
end
