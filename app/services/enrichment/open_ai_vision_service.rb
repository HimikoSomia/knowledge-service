require "openai"
require "base64"
require "open3"

# OpenAI vision service for image descriptions.
#
# For each image_ref section this service:
#   1. Renders the relevant page (PDF) or uses the uploaded file directly (image files).
#   2. Base64-encodes the image and sends it to the OpenAI Chat Completions API.
#   3. Returns a plain-text description suitable for chunking and embedding.
#
# Configuration:
#   OPENAI_API_KEY          — required (shared with embedding service)
#   OPENAI_VISION_MODEL     — default: "gpt-4o-mini"
#
class Enrichment::OpenAiVisionService
  Error = Class.new(StandardError)
  ConfigurationError = Class.new(Error)
  TransientError = Class.new(Error)

  class PermanentImageError < Error
    attr_reader :code

    def initialize(message = "The image cannot be enriched.", code: "image_unavailable")
      @code = code
      super(message)
    end
  end

  # Render pages at 150 DPI — sufficient for vision without excessive file size.
  RENDER_DPI = "150"

  def configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def vision_model
    @vision_model ||= ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini")
  end

  # Analyzes the image identified by image_ref and returns a descriptive string.
  # Raises a classified error when image preparation or the provider call fails.
  def describe_image_from_document(document, image_ref)
    page_number  = image_ref["page_number"].to_i
    source_type  = image_ref["source_type"].to_s

    data_url = extract_image_data_url(document, page_number, source_type)
    unless data_url
      raise PermanentImageError.new(
        "The image data could not be prepared.",
        code: "image_unavailable"
      )
    end

    call_vision_api(data_url, description_prompt)
  end

  private

  # ── Image extraction ──────────────────────────────────────────────────────

  def extract_image_data_url(document, page_number, source_type)
    if source_type == "uploaded"
      # The document IS the image — use the uploaded file directly.
      uploaded_image_data_url(document)
    else
      # PDF or other compound document — render the page as PNG.
      render_pdf_page_data_url(document, page_number)
    end
  end

  def uploaded_image_data_url(document)
    document.file.blob.open do |tmp|
      data = File.binread(tmp.path)
      mime = document.file.blob.content_type
      "data:#{mime};base64,#{Base64.strict_encode64(data)}"
    end
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise TransientError, "Image storage is temporarily unavailable."
  rescue
    raise PermanentImageError.new(
      "The uploaded image could not be read.",
      code: "image_unreadable"
    )
  end

  def render_pdf_page_data_url(document, page_number)
    unless pdftoppm_available?
      raise PermanentImageError.new(
        "PDF image rendering is unavailable.",
        code: "renderer_unavailable"
      )
    end

    document.file.blob.open do |tmp|
      Dir.mktmpdir("ks_vision_") do |dir|
        prefix = File.join(dir, "page")
        _, _error_output, status = Open3.capture3(
          "pdftoppm",
          "-f", page_number.to_s,
          "-l", page_number.to_s,
          "-r", RENDER_DPI,
          "-png",
          tmp.path,
          prefix
        )

        unless status.success?
          raise PermanentImageError.new(
            "The PDF page could not be rendered.",
            code: "render_failed"
          )
        end

        page_file = Dir.glob(File.join(dir, "page-*.png")).first
        unless page_file
          raise PermanentImageError.new(
            "The rendered PDF page was not produced.",
            code: "render_missing"
          )
        end

        data = File.binread(page_file)
        "data:image/png;base64,#{Base64.strict_encode64(data)}"
      end
    end
  rescue PermanentImageError, TransientError
    raise
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise TransientError, "Document storage is temporarily unavailable."
  rescue
    raise PermanentImageError.new(
      "The PDF page could not be read.",
      code: "render_failed"
    )
  end

  # ── Vision API call ───────────────────────────────────────────────────────

  def call_vision_api(image_data_url, prompt)
    response = client.chat(
      parameters: {
        model:      vision_model,
        messages:   [
          {
            role:    "user",
            content: [
              { type: "image_url", image_url: { url: image_data_url, detail: "auto" } },
              { type: "text", text: prompt }
            ]
          }
        ],
        max_tokens: 1500
      }
    )

    text = response.dig("choices", 0, "message", "content")&.strip
    raise TransientError, "The Vision provider returned an empty response." if text.blank?

    text
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    raise TransientError, "The Vision provider is temporarily unavailable."
  rescue Faraday::ClientError => e
    handle_openai_error(e)
  rescue OpenAI::Error => e
    handle_openai_error(e)
  end

  def description_prompt
    <<~PROMPT.strip
      Analyze this image from a document and describe its content in detail.

      - If the image contains readable text, transcribe it accurately.
      - If the image shows a chart or graph, describe the data, axis labels, trends, and key values.
      - If the image shows a table, list the headers and row contents.
      - If the image shows a diagram, flowchart, or schematic, explain its structure and meaning.
      - If the image shows a form, identify the labels and any filled-in values.
      - If the image is a photograph or illustration, describe what is depicted.

      Be thorough and specific. The description will be used to make this content
      searchable and retrievable by an AI assistant answering questions about this document.
    PROMPT
  end

  def client
    @client ||= OpenAI::Client.new(
      access_token:    ENV.fetch("OPENAI_API_KEY"),
      request_timeout: 60
    )
  end

  def handle_openai_error(error)
    response = error.response if error.respond_to?(:response)
    status = if response.respond_to?(:dig)
      response.dig(:status) || response.dig("status")
    elsif response.respond_to?(:status)
      response.status
    end

    case status
    when 400, 404, 413, 422
      raise PermanentImageError.new(
        "The Vision provider rejected this image.",
        code: "provider_rejected_image"
      )
    when 401, 403
      raise ConfigurationError, "Vision provider authentication failed."
    when 408, 409, 425, 429, 500..599
      raise TransientError, "The Vision provider is temporarily unavailable."
    else
      raise TransientError, "The Vision provider returned an unexpected error."
    end
  end

  def pdftoppm_available?
    @pdftoppm ||= system("which pdftoppm > /dev/null 2>&1")
  end
end
