# OpenAI GPT-4o Vision implementation of Enrichment::VisionService.
#
# Stub — implement #describe_image_from_document when the OpenAI API key is
# configured and the ruby-openai gem (or equivalent HTTP client) is available.
#
# The interface this method must fulfil:
#   1. Re-extract the image from document.file using image_ref["page_number"] and
#      image_ref["image_index"] (via Extraction::PdfImageExtractor or similar).
#   2. Base64-encode the image and POST it to the OpenAI Chat Completions API
#      with a vision-capable model (e.g. "gpt-4o") and a structured prompt
#      asking for a description of the image content.
#   3. Return the description string from the API response.
#   4. Return nil on error (caller logs and continues).
#
class Enrichment::OpenAiVisionService < Enrichment::VisionService
  def configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def describe_image_from_document(_document, _image_ref)
    raise NotImplementedError,
      "Enrichment::OpenAiVisionService#describe_image_from_document is not yet implemented. " \
      "See the class comment for the expected implementation steps."
  end
end
