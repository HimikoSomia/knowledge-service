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
  VisionError = Class.new(StandardError)

  # Render pages at 150 DPI — sufficient for vision without excessive file size.
  RENDER_DPI = "150"

  def configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def vision_model
    @vision_model ||= ENV.fetch("OPENAI_VISION_MODEL", "gpt-4o-mini")
  end

  # Analyzes the image identified by image_ref and returns a descriptive string.
  # Returns nil when the image cannot be accessed or the API call fails.
  def describe_image_from_document(document, image_ref)
    page_number  = image_ref["page_number"].to_i
    source_type  = image_ref["source_type"].to_s

    data_url = extract_image_data_url(document, page_number, source_type)
    return nil if data_url.nil?

    call_vision_api(data_url, description_prompt)
  rescue VisionError => e
    Rails.logger.error "OpenAiVisionService: vision API failed for document #{document.id} " \
                       "page #{page_number}: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "OpenAiVisionService: unexpected error for document #{document.id}: #{e.message}"
    nil
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
  rescue => e
    Rails.logger.warn "OpenAiVisionService: could not read uploaded image: #{e.message}"
    nil
  end

  def render_pdf_page_data_url(document, page_number)
    return nil unless pdftoppm_available?

    document.file.blob.open do |tmp|
      Dir.mktmpdir("ks_vision_") do |dir|
        prefix = File.join(dir, "page")
        _, err, status = Open3.capture3(
          "pdftoppm",
          "-f", page_number.to_s,
          "-l", page_number.to_s,
          "-r", RENDER_DPI,
          "-png",
          tmp.path,
          prefix
        )

        unless status.success?
          Rails.logger.warn "OpenAiVisionService: pdftoppm failed for page #{page_number}: #{err.strip}"
          return nil
        end

        page_file = Dir.glob(File.join(dir, "page-*.png")).first
        return nil unless page_file

        data = File.binread(page_file)
        "data:image/png;base64,#{Base64.strict_encode64(data)}"
      end
    end
  rescue => e
    Rails.logger.warn "OpenAiVisionService: page render failed: #{e.message}"
    nil
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
    text.blank? ? nil : text
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise VisionError, "Network error: #{e.message}"
  rescue OpenAI::Error => e
    status  = e.response&.dig(:status)
    raise VisionError, "OpenAI API error (HTTP #{status}): #{e.message}"
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

  def pdftoppm_available?
    @pdftoppm ||= system("which pdftoppm > /dev/null 2>&1")
  end
end
