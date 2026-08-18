class Extraction::DocumentExtractor
  UnsupportedTypeError = Class.new(ArgumentError)

  FORMATS = [
    { type: "txt", extractor: Extraction::PlainTextExtractor, content_types: %w[text/plain], extensions: %w[txt] },
    { type: "md", extractor: Extraction::PlainTextExtractor, content_types: %w[text/markdown], extensions: %w[md markdown] },
    { type: "csv", extractor: Extraction::CsvExtractor, content_types: %w[text/csv], extensions: %w[csv] },
    { type: "json", extractor: Extraction::JsonExtractor, content_types: %w[application/json], extensions: %w[json] },
    { type: "html", extractor: Extraction::HtmlExtractor, content_types: %w[text/html application/xhtml+xml], extensions: %w[html htm] },
    { type: "xml", extractor: Extraction::HtmlExtractor, content_types: %w[application/xml text/xml], extensions: %w[xml] },
    { type: "pdf", extractor: Extraction::PdfExtractor, content_types: %w[application/pdf], extensions: %w[pdf] },
    {
      type: "docx",
      extractor: Extraction::DocxExtractor,
      content_types: %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document],
      extensions: %w[docx]
    },
    {
      type: "xlsx",
      extractor: Extraction::XlsxExtractor,
      content_types: %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet],
      extensions: %w[xlsx]
    },
    { type: "xls", extractor: Extraction::XlsxExtractor, content_types: %w[application/vnd.ms-excel], extensions: %w[xls] },
    {
      type: "ods",
      extractor: Extraction::XlsxExtractor,
      content_types: %w[application/vnd.oasis.opendocument.spreadsheet],
      extensions: %w[ods]
    },
    {
      type: "pptx",
      extractor: Extraction::PptxExtractor,
      content_types: %w[application/vnd.openxmlformats-officedocument.presentationml.presentation],
      extensions: %w[pptx]
    },
    { type: "jpeg", extractor: Extraction::ImageExtractor, content_types: %w[image/jpeg image/jpg], extensions: %w[jpg jpeg] },
    { type: "png", extractor: Extraction::ImageExtractor, content_types: %w[image/png], extensions: %w[png] },
    { type: "webp", extractor: Extraction::ImageExtractor, content_types: %w[image/webp], extensions: %w[webp] },
    { type: "gif", extractor: Extraction::ImageExtractor, content_types: %w[image/gif], extensions: %w[gif] },
    { type: "tiff", extractor: Extraction::ImageExtractor, content_types: %w[image/tiff], extensions: %w[tif tiff] },
    { type: "bmp", extractor: Extraction::ImageExtractor, content_types: %w[image/bmp], extensions: %w[bmp] },
    { type: "heic", extractor: Extraction::ImageExtractor, content_types: %w[image/heic], extensions: %w[heic] },
    { type: "heif", extractor: Extraction::ImageExtractor, content_types: %w[image/heif], extensions: %w[heif] }
  ].freeze

  CONTENT_TYPE_INDEX = FORMATS.each_with_object({}) do |format, index|
    format[:content_types].each { |content_type| index[content_type] = format }
  end.freeze

  EXTENSION_INDEX = FORMATS.each_with_object({}) do |format, index|
    format[:extensions].each { |extension| index[extension] = format }
  end.freeze

  class << self
    def supported?(blob)
      format_for(blob).present?
    end

    def document_type_for(blob)
      extension = file_extension(blob)
      return extension if EXTENSION_INDEX.key?(extension)

      CONTENT_TYPE_INDEX.dig(blob.content_type, :type)
    end

    def format_for(blob)
      CONTENT_TYPE_INDEX[blob.content_type] || EXTENSION_INDEX[file_extension(blob)]
    end

    private

    def file_extension(blob)
      File.extname(blob.filename.to_s).delete_prefix(".").downcase
    end
  end

  def for(blob)
    format = self.class.format_for(blob)
    return format[:extractor].new if format

    raise UnsupportedTypeError, "Unsupported document type: #{blob.content_type.inspect}"
  end
end
